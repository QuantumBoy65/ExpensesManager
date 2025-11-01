import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await AndroidAlarmManager.initialize();
    // Planifier la clôture automatique chaque jour à 5h
    await planifierClotureAutomatique();
  }

  runApp(MyApp());
}

// Fonction planifiant la tâche automatique
Future<void> planifierClotureAutomatique() async {
  final now = DateTime.now();

  // Calculer la prochaine exécution à 5h du matin
  DateTime prochaine = DateTime(now.year, now.month, now.day, 5);
  if (now.isAfter(prochaine)) {
    prochaine = prochaine.add(Duration(days: 1));
  }

  final difference = prochaine.difference(now);

  await AndroidAlarmManager.periodic(
    Duration(days: 1),
    0, // identifiant unique
    cloturerJourneeAutomatique,
    startAt: DateTime.now().add(difference),
    exact: true,
    wakeup: true,
  );
}

// Fonction exécutée automatiquement à 5h du matin
void cloturerJourneeAutomatique() async {
  final prefs = await SharedPreferences.getInstance();

  List<Map<String, dynamic>> depensesJour =
      (jsonDecode(prefs.getString('depensesJour') ?? '[]')).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> historique =
      (jsonDecode(prefs.getString('historique') ?? '[]')).cast<Map<String, dynamic>>();

  if (depensesJour.isNotEmpty) {
    String dateJournee = DateTime.now().toString().substring(0, 10);
    int total = depensesJour.fold(0, (sum, item) => sum + (item['prix'] as int));

    historique.add({'date': dateJournee, 'total': total});

    await prefs.setString('depensesJour', jsonEncode([]));
    await prefs.setString('historique', jsonEncode(historique));
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion de Dépenses',
      theme: ThemeData(primarySwatch: Colors.green),
      home: ProductPage(),
    );
  }
}

class ProductPage extends StatefulWidget {
  @override
  _ProductPageState createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _prixController = TextEditingController();

  List<Map<String, dynamic>> depensesJour = [];
  List<Map<String, dynamic>> historique = [];

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  Future<void> _chargerDonnees() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      historique = (jsonDecode(prefs.getString('historique') ?? '[]')).cast<Map<String, dynamic>>();
      depensesJour = (jsonDecode(prefs.getString('depensesJour') ?? '[]')).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _sauvegarderDonnees() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('depensesJour', jsonEncode(depensesJour));
    await prefs.setString('historique', jsonEncode(historique));
  }

  void _ajouterProduit() {
    String nom = _nomController.text.trim();
    int? prix = int.tryParse(_prixController.text.trim());

    if (nom.isEmpty || prix == null) return;

    setState(() {
      depensesJour.add({'nom': nom, 'prix': prix});
    });

    _sauvegarderDonnees();
    _nomController.clear();
    _prixController.clear();
  }

  int _totalDuJour() {
    return depensesJour.fold(0, (sum, item) => sum + (item['prix'] as int));
  }

  void _cloturerJournee() async {
    if (depensesJour.isEmpty) return;

    String dateJournee = DateTime.now().toString().substring(0, 10);
    int total = _totalDuJour();

    setState(() {
      historique.add({'date': dateJournee, 'total': total});
      depensesJour.clear();
    });

    await _sauvegarderDonnees();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Journée clôturée : $total F ajoutés à l’historique')),
    );
  }

  void _ouvrirHistorique() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoriquePage(historique: historique),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateAujourdhui = DateTime.now().toString().substring(0, 10);

    return Scaffold(
      appBar: AppBar(
        title: Text('Dépenses du $dateAujourdhui'),
        actions: [
          IconButton(icon: Icon(Icons.history), onPressed: _ouvrirHistorique),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Total permanent en haut
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '💰 Total du jour : ${_totalDuJour()} F',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),

            // 🔹 Champs de saisie
            TextField(
              controller: _nomController,
              decoration: InputDecoration(labelText: 'Nom du produit'),
            ),
            TextField(
              controller: _prixController,
              decoration: InputDecoration(labelText: 'Prix'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ajouterProduit,
              child: Text('Ajouter'),
            ),
            SizedBox(height: 20),

            // 🔹 Liste des dépenses
            Expanded(
              child: ListView(
                children: depensesJour.map((dep) {
                  return ListTile(
                    title: Text(dep['nom']),
                    trailing: Text('${dep['prix']} F'),
                  );
                }).toList(),
              ),
            ),

            // 🔹 Bouton de clôture
            Divider(),
            Center(
              child: ElevatedButton(
                onPressed: _cloturerJournee,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                child: Text('Clôturer la journée'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoriquePage extends StatelessWidget {
  final List<Map<String, dynamic>> historique;

  HistoriquePage({required this.historique});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Historique des dépenses')),
      body: historique.isEmpty
          ? Center(child: Text('Aucune journée enregistrée'))
          : ListView.builder(
              itemCount: historique.length,
              itemBuilder: (context, index) {
                final entry = historique[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    title: Text('Date : ${entry['date']}'),
                    trailing: Text('${entry['total']} F'),
                  ),
                );
              },
            ),
    );
  }
}
