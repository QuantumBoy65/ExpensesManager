import 'package:flutter/material.dart';
//import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // pour encoder/décoder en JSON
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(const MyApp());
}
// la création de la  base de donnée
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses.db');
    return _database!;
  }
  // Sauvegarder un total journalier pour une date donnée (dateString au format 'YYYY-MM-DD')
  Future<void> insertHistoryForDate(String dateString, double total) async {
    final db = await instance.database;
    await db.insert('history', {
      'date': dateString,
      'total': total,
    });
  }


  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        date TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        total REAL NOT NULL
      );
    ''');
  }

  // 🔹 Ajouter une dépense
  Future<void> insertExpense(String name, double price) async {
    final db = await instance.database;
    await db.insert('expenses', {
      'name': name,
      'price': price,
      'date': DateTime.now().toIso8601String(),
    });
  }

  // 🔹 Récupérer toutes les dépenses
  Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await instance.database;
    return await db.query(
      'expenses',
      orderBy: 'date DESC',
    );

  }

  // 🔹 Supprimer toutes les dépenses (quand tu sauvegardes la journée)
  Future<void> clearExpenses() async {
    final db = await instance.database;
    await db.delete('expenses');
  }

  // 🔹 Sauvegarder un total journalier
  Future<void> insertHistory(double total) async {
    final db = await instance.database;
    await db.insert('history', {
      'date': DateTime.now().toIso8601String(),
      'total': total,
    });
  }

  // 🔹 Récupérer l’historique complet
  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await instance.database;
    return await db.query('history', orderBy: 'id DESC');
  }
}



class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expenses Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
       // colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),

        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(155, 183, 133, 58)),
        ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _history = [];
  double _total = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // d'abord vérifier/fermer les journées précédentes (si besoin), puis charger les données
    _checkAndCloseDay().then((_) => _loadData());
  }


// Automatisation de la cloture des dépenses journaliere
  
    Future<void> _checkAndCloseDay() async {
      // dbHelper : instance de DatabaseHelper
      final now = DateTime.now();

      // business day courante : si heure >= 5 => today, sinon => yesterday
      String currentBusinessDay;
      if (now.hour >= 0) {
        currentBusinessDay = DateTime(now.year, now.month, now.day).toIso8601String().substring(0,10);
      } else {
        final yesterday = now.subtract(Duration(days: 1));
        currentBusinessDay = DateTime(yesterday.year, yesterday.month, yesterday.day).toIso8601String().substring(0,10);
      }

      // Récupérer toutes les dépenses
      final allExpenses = await dbHelper.getExpenses(); // retourne liste avec 'date' (iso string) et 'price'
      if (allExpenses.isEmpty) return;

      // Construire un map: businessDay -> list of expenses
      Map<String, List<Map<String, dynamic>>> grouped = {};

      for (var e in allExpenses) {
        final String dateStr = e['date']; // iso string
        final DateTime dt = DateTime.parse(dateStr);

        // calculer business day de cette dépense :
        String businessDay;
        if (dt.hour >= 0) {
          businessDay = DateTime(dt.year, dt.month, dt.day).toIso8601String().substring(0,10);
        } else {
          final d = dt.subtract(Duration(days: 1));
          businessDay = DateTime(d.year, d.month, d.day).toIso8601String().substring(0,10);
        }

        grouped.putIfAbsent(businessDay, () => []);
        grouped[businessDay]!.add(e);
      }

      // Trouver toutes les businessDay antérieures à la business day courante
      final daysToClose = grouped.keys.where((bd) => bd.compareTo(currentBusinessDay) < 0).toList();
      if (daysToClose.isEmpty) return; // rien à fermer (évite le problème au 1er lancement)

      // Pour chaque jour à clôturer : somme, insert historique (avec la date du businessDay),
      // puis supprimer les dépenses correspondantes
      for (var bd in daysToClose) {
        final list = grouped[bd]!;
        double total = 0;
        for (var item in list) {
          total += (item['price'] as num).toDouble();
        }

        // Insérer l'historique pour la date bd (au format YYYY-MM-DD)
        await dbHelper.insertHistoryForDate(bd, total);

        // Supprimer ces dépenses : on peut supprimer par id si disponible,
        // sinon supprimer toutes les dépenses dont la businessDay == bd.
        // Ici on supprime par id si 'id' champ présent :
        final ids = list.map((x) => x['id']).where((id) => id != null).toList();
        if (ids.isNotEmpty) {
          final db = await dbHelper.database;
          // Construire clause WHERE id IN (...)
          final placeholders = List.filled(ids.length, '?').join(',');
          await db.delete('expenses', where: 'id IN ($placeholders)', whereArgs: ids);
        } else {
          // Fallback : supprimer par plage de date (par sécurité)
          for (var item in list) {
            final db = await dbHelper.database;
            await db.delete('expenses', where: 'date = ?', whereArgs: [item['date']]);
          }
        }
      }
    }


// mise en jour des données
  Future<void> _loadData() async {
    final expenses = await dbHelper.getExpenses();
    final history = await dbHelper.getHistory();
    double total = 0;

    for (var e in expenses) {
      total += e['price'];
    }
    setState(() {
      _expenses = expenses;
      _history = history;
      _total = total;
    });
  }

  Future<void> _addExpense(String name, double price) async {
    await dbHelper.insertExpense(name, price);
    await _loadData();
  }

  Future<void> _saveToHistory() async {
    if (_total > 0) {
      await dbHelper.insertHistory(_total);
      await dbHelper.clearExpenses();
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        expenses: _expenses,
        total: _total,
        onAddExpense: _addExpense,
        onSaveToHistory: _saveToHistory,
      ),
      HistoryPage(history: _history),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historique'),
        ],
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  final List<Map<String, dynamic>> expenses;
  final double total;
  final Function(String, double) onAddExpense;
  final VoidCallback onSaveToHistory;

  const HomePage({
    super.key,
    required this.expenses,
    required this.total,
    required this.onAddExpense,
    required this.onSaveToHistory,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _productController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  void _addExpense() {
    if (_priceController.text.isNotEmpty) {
      double? price = double.tryParse(_priceController.text);
      if (price != null) {
        widget.onAddExpense(_productController.text, price);
        _productController.clear();
        _priceController.clear();
      }
    }
  }
  // ✅ Fonction pour formater la date (ajoutée)
  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    String year = date.year.toString();
    String hour = date.hour.toString().padLeft(2, '0');
    String minute = date.minute.toString().padLeft(2, '0');
    String second = date.second.toString().padLeft(2, '0');
    return "$day/$month/$year à $hour:$minute:$second";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses Quotidiennes',
        style: TextStyle(color: Colors.brown),
      ),
        backgroundColor: Color(0xFFF5F5DC),
        elevation: 5

      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            TextField(
              controller: _productController,
              decoration: const InputDecoration(labelText: 'Nom ou catégorie du produit'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Prix'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _addExpense, child: const Text('Ajouter')),
            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: widget.expenses.length,
                itemBuilder: (context, index) {
                  final e = widget.expenses[index];
                  return ListTile(
                    title: Text(e['name']),
                    subtitle: Text("${e['price']} F"),
                    trailing: Text(
                      _formatDate(e['date']), // ✅ affiche la date exacte
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                },
              ),
            ),


            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                " 💰 Aujourd'hui : ${widget.total.toStringAsFixed(2)} F",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                /*'💰 Total du jour : ${_totalDuJour()} F',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),*/
                textAlign: TextAlign.center,
              ),
            ),
            /*ElevatedButton(
              onPressed: widget.onSaveToHistory,
              child: const Text('Sauvegarder dans Historique'),
            ),*/
          ],
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const HistoryPage({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des Dépenses',
      style: TextStyle(color: Colors.brown),
      ),
          backgroundColor: Color(0xFFF5F5DC),
        elevation: 5
      ),
      body: history.isEmpty
          ? const Center(
          child: Text('Aucun historique pour le moment',
              style: TextStyle(fontSize: 16)))
          : ListView.builder(
        itemCount: history.length,
        itemBuilder: (context, index) {
          final item = history[index];
          final date = DateTime.parse(item['date']);
          return Card(
            margin:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading:
              const Icon(Icons.calendar_today, color: Colors.teal),
              title: Text(
                  "Date : ${date.day}/${date.month}/${date.year}"),
              subtitle: Text(
                "Total : ${item['total'].toStringAsFixed(2)} F",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    );
  }
}
