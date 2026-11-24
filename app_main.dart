import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

const green = Color(0xFF22C55E);
late SharedPreferences prefs;
List<Map<String, dynamic>> notes = [], tasks = [];
List<String> folders = [];

void save() => prefs.setString('nb', jsonEncode({'n': notes, 't': tasks, 'f': folders}));
List<Map<String, dynamic>> _ld(dynamic l) => List<Map<String, dynamic>>.from((l ?? []).map((e) => Map<String, dynamic>.from(e)));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  final s = prefs.getString('nb');
  if (s != null) {
    final d = jsonDecode(s);
    notes = _ld(d['n']);
    tasks = _ld(d['t']);
    folders = List<String>.from(d['f'] ?? []);
  }
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Notes',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(primary: green),
    ),
    home: const Home(),
  ));
}

String plain(Map n) => ((n['blocks'] ?? []) as List).where((b) => b['t'] == 'text').map((b) => b['v']).join(' ').trim();
String fd(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t), n = DateTime.now();
  String z(int x) => x.toString().padLeft(2, '0');
  return d.day == n.day && d.month == n.month && d.year == n.year ? '${z(d.hour)}:${z(d.minute)}' : '${z(d.month)}/${z(d.day)}';
}

Future<String?> choose(BuildContext c, String title, List<String> o) => showModalBottomSheet<String>(
    context: c,
    builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
      Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontSize: 20))),
      for (final x in o) ListTile(title: Text(x), onTap: () => Navigator.pop(c, x)),
    ])));

Future<String?> ask(BuildContext c, String title, {String init = ''}) {
  final t = TextEditingController(text: init);
  return showDialog<String>(
      context: c,
      builder: (_) => AlertDialog(
            title: Text(title),
            content: TextField(controller: t, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.pop(c, t.text.trim()), child: const Text('OK')),
            ],
          ));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _H();
}

class _H extends State<Home> {
  int tab = 0;
  String flt = 'all';
  Set<String> sel = {};
  final q = TextEditingController();
  bool get selMode => sel.isNotEmpty;

  List<Map<String, dynamic>> get list {
    final l = notes
        .where((n) => flt == 'trash' ? n['del'] == true : n['del'] != true)
        .where((n) => flt == 'all' || flt == 'trash' || (flt == 'none' ? (n['folder'] ?? '') == '' : n['folder'] == flt))
        .where((n) => '${n['title']} ${plain(n)}'.toLowerCase().contains(q.text.toLowerCase()))
        .toList();
    l.sort((a, b) {
      final p = (b['pin'] == true ? 1 : 0) - (a['pin'] == true ? 1 : 0);
      return p != 0 ? p : (b['t'] as int).compareTo(a['t'] as int);
    });
    return l;
  }

  String get name => tab == 1 ? 'Tâche' : flt == 'all' ? 'Toutes les notes' : flt == 'none' ? 'Sans nom' : flt == 'trash' ? 'Supprimé récemment' : flt;

  Future<void> open(Map<String, dynamic> n) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => Editor(n)));
    notes.removeWhere((x) => x['title'] == '' && plain(x) == '' && (x['blocks'] as List).every((b) => b['t'] == 'text'));
    save();
    setState(() {});
  }

  void menu() => showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
        for (final e in {'all': 'Toutes les notes', 'none': 'Sans nom', 'trash': 'Supprimé récemment'}.entries)
          ListTile(title: Text(e.value), selected: flt == e.key, onTap: () { Navigator.pop(context); setState(() => flt = e.key); }),
        const Divider(),
        ListTile(title: const Text('Dossiers'), trailing: const Icon(Icons.add), onTap: () async {
          Navigator.pop(context);
          final n = await ask(context, 'Nom du dossier');
          if (n != null && n.isNotEmpty && !folders.contains(n)) { folders.add(n); save(); setState(() {}); }
        }),
        for (final f in folders) ListTile(leading: const Icon(Icons.folder_outlined), title: Text(f), selected: flt == f, onTap: () { Navigator.pop(context); setState(() => flt = f); }),
      ])));

  void act(String a) async {
    final ns = notes.where((n) => sel.contains(n['id'])).toList();
    if (a == 'pin') { final all = ns.every((n) => n['pin'] == true); for (final n in ns) n['pin'] = !all; }
    if (a == 'del') { for (final n in ns) { if (n['del'] == true) notes.remove(n); else n['del'] = true; } }
    if (a == 'mov') {
      final f = await choose(context, 'Déplacer vers', ['Sans nom', ...folders]);
      if (f == null) return;
      for (final n in ns) n['folder'] = f == 'Sans nom' ? '' : f;
    }
    save();
    setState(() => sel = {});
  }

  @override
  Widget build(BuildContext c) {
    final l = list;
    return Scaffold(
      body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InkWell(
                onTap: tab == 0 && !selMode ? menu : null,
                child: Text(selMode ? '${sel.length} sélectionné(s)' : name + (tab == 0 ? ' ▾' : ''), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w500)))),
        Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
                controller: q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Rechercher', filled: true, fillColor: const Color(0xFF161616), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
        Expanded(
            child: tab == 1
                ? ListView(children: [
                    for (final t in tasks.where((t) => '${t['t']}'.toLowerCase().contains(q.text.toLowerCase())))
                      ListTile(
                        leading: IconButton(icon: Icon(t['d'] == true ? Icons.check_circle : Icons.circle_outlined, color: t['d'] == true ? green : Colors.grey), onPressed: () { t['d'] = !(t['d'] == true); save(); setState(() {}); }),
                        title: Text(t['t'], style: TextStyle(fontSize: 20, decoration: t['d'] == true ? TextDecoration.lineThrough : null)),
                        onTap: () async { final v = await ask(c, 'Modifier la tâche', init: t['t']); if (v != null && v.isNotEmpty) { t['t'] = v; save(); setState(() {}); } },
                        trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { tasks.remove(t); save(); setState(() {}); }),
                      )
                  ])
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
                    for (final n in l)
                      InkWell(
                        onLongPress: () => setState(() => sel.add(n['id'])),
                        onTap: () => selMode ? setState(() => sel.contains(n['id']) ? sel.remove(n['id']) : sel.add(n['id'])) : open(n),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
                          child: Row(children: [
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n['title'] != '' ? n['title'] : (plain(n).isEmpty ? 'Sans titre' : plain(n)), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 10),
                              Row(children: [if (n['pin'] == true) const Icon(Icons.push_pin_outlined, color: green, size: 20), const SizedBox(width: 6), Text(fd(n['t']), style: const TextStyle(color: Colors.grey, fontSize: 16))]),
                              const SizedBox(height: 8),
                              Row(children: [const Icon(Icons.folder_outlined, size: 20, color: Colors.grey), const SizedBox(width: 8), Text((n['folder'] ?? '') == '' ? 'Sans nom' : n['folder'], style: const TextStyle(color: Colors.grey, fontSize: 16))]),
                            ])),
                            if (selMode) Icon(sel.contains(n['id']) ? Icons.check_box : Icons.check_box_outline_blank, color: sel.contains(n['id']) ? green : Colors.grey),
                          ]),
                        ),
                      )
                  ])),
      ])),
      floatingActionButton: selMode
          ? null
          : FloatingActionButton(
              backgroundColor: const Color(0xFF2A2D2A),
              foregroundColor: green,
              onPressed: () async {
                if (tab == 1) { final v = await ask(c, 'Nouvelle tâche'); if (v != null && v.isNotEmpty) { tasks.insert(0, {'t': v, 'd': false}); save(); setState(() {}); } return; }
                final n = <String, dynamic>{'id': DateTime.now().microsecondsSinceEpoch.toString(), 'title': '', 'blocks': [{'t': 'text', 'v': ''}], 'folder': ['all', 'none', 'trash'].contains(flt) ? '' : flt, 'pin': false, 'del': false, 't': DateTime.now().millisecondsSinceEpoch};
                notes.add(n);
                open(n);
              },
              child: const Icon(Icons.add, size: 34)),
      bottomNavigationBar: selMode
          ? BottomAppBar(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              TextButton.icon(onPressed: () => act('pin'), icon: const Icon(Icons.push_pin_outlined), label: const Text('Épingler')),
              TextButton.icon(onPressed: () => act('mov'), icon: const Icon(Icons.drive_file_move_outline), label: const Text('Déplacer')),
              TextButton.icon(onPressed: () => act('del'), icon: const Icon(Icons.delete_outline), label: const Text('Supprimer')),
            ]))
          : NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
              NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description, color: green), label: 'Notes'),
              NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle, color: green), label: 'Tâche'),
            ]),
    );
  }
}

class AudioTile extends StatefulWidget {
  final String path;
  const AudioTile(this.path, {super.key});
  @override
  State<AudioTile> createState() => _A();
}

class _A extends State<AudioTile> {
  final p = AudioPlayer();
  bool on = false;
  @override
  void initState() {
    super.initState();
    p.onPlayerComplete.listen((_) => setState(() => on = false));
  }
  @override
  void dispose() { p.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: IconButton(icon: Icon(on ? Icons.pause_circle : Icons.play_circle, color: green, size: 36), onPressed: () async {
          if (on) { await p.pause(); } else { await p.play(DeviceFileSource(widget.path)); }
          setState(() => on = !on);
        }),
        title: const Text('Note vocale'),
      ));
}

class Editor extends StatefulWidget {
  final Map<String, dynamic> n;
  const Editor(this.n, {super.key});
  @override
  State<Editor> createState() => _E();
}

class _E extends State<Editor> {
  late List<Map<String, dynamic>> bl;
  late List<TextEditingController?> cs;
  final title = TextEditingController();
  final sp = SpeechToText();
  final rec = AudioRecorder();
  bool dic = false, recing = false;
  int act = 0;
  String live = '';

  @override
  void initState() {
    super.initState();
    bl = _ld(widget.n['blocks']);
    if (bl.isEmpty || bl.last['t'] != 'text') bl.add({'t': 'text', 'v': ''});
    cs = bl.map((b) => b['t'] == 'text' ? TextEditingController(text: b['v']) : null).toList();
    title.text = widget.n['title'];
    act = bl.length - 1;
  }

  void commit() {
    widget.n['title'] = title.text;
    widget.n['blocks'] = [for (var i = 0; i < bl.length; i++) bl[i]['t'] == 'text' ? {'t': 'text', 'v': cs[i]!.text} : bl[i]];
    widget.n['t'] = DateTime.now().millisecondsSinceEpoch;
    save();
  }

  void msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  String fix(String t) {
    final cmd = [
      [r"point d'interrogation", '?'], [r"point d'exclamation", '!'], [r'deux[- ]points', ' :'], [r'point[- ]virgule', ' ;'],
      [r'points de suspension', '…'], [r'virgule', ','], [r'à la ligne|nouvelle ligne', '\n'], [r'point final|point', '.'],
    ];
    for (final c in cmd) { t = t.replaceAll(RegExp('(?<!\\p{L})(?:${c[0]})(?!\\p{L})', caseSensitive: false, unicode: true), c[1]); }
    t = t.replaceAllMapped(RegExp(r'\s+([,.!?;:…)])'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'([,.!?;…])(?=[^\s,.!?;…)\n])'), (m) => '${m[1]} ');
    t = t.replaceAll(RegExp(r' ?\n ?'), '\n').replaceAll(RegExp(r' {2,}'), ' ').trim();
    t = t.replaceAllMapped(RegExp(r'([.!?…]\s+|\n)(\p{L})', unicode: true), (m) => m[1]! + m[2]!.toUpperCase());
    return t;
  }

  void ins(String raw) {
    final c = cs[act]!;
    final i = c.selection.isValid ? c.selection.end : c.text.length;
    final pre = c.text.substring(0, i);
    var t = fix(raw);
    if (t.isEmpty) return;
    if (pre.trim().isEmpty || RegExp(r'[.!?…]\s*$').hasMatch(pre)) t = t[0].toUpperCase() + t.substring(1);
    final sp1 = pre.isNotEmpty && !RegExp(r'[\s(]$').hasMatch(pre) && !t.startsWith('\n') ? ' ' : '';
    final nt = pre + sp1 + t;
    c.value = TextEditingValue(text: nt + c.text.substring(i), selection: TextSelection.collapsed(offset: nt.length));
  }

  void listen() {
    if (sp.isListening) return;
    sp.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 6),
      listenOptions: SpeechListenOptions(onDevice: true, partialResults: true, cancelOnError: false, listenMode: ListenMode.dictation),
      onResult: (r) {
        if (r.finalResult) { ins(r.recognizedWords); live = ''; } else { live = r.recognizedWords; }
        setState(() {});
      },
    );
  }

  Future<void> toggleDic() async {
    if (dic) { dic = false; live = ''; await sp.stop(); setState(() {}); return; }
    final ok = await sp.initialize(
      onStatus: (s) { if (dic && (s == 'done' || s == 'notListening')) Future.delayed(const Duration(milliseconds: 300), () { if (dic) listen(); }); },
      onError: (e) => msg('Dictée : ${e.errorMsg}. Vérifiez le pack français hors ligne.'),
    );
    if (!ok) { msg('Reconnaissance vocale indisponible'); return; }
    dic = true;
    setState(() {});
    listen();
  }

  void addBlock(Map<String, dynamic> b) {
    final i = act + 1;
    bl.insert(i, b); cs.insert(i, null);
    bl.insert(i + 1, {'t': 'text', 'v': ''}); cs.insert(i + 1, TextEditingController());
    act = i + 1;
    setState(() {});
  }

  Future<void> pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
    if (f == null) return;
    final d = await getApplicationDocumentsDirectory();
    final p = '${d.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(f.path).copy(p);
    addBlock({'t': 'img', 'p': p, 'w': 1.0, 'r': 12.0, 'b': false});
  }

  Future<void> toggleRec() async {
    if (recing) {
      final p = await rec.stop();
      recing = false;
      if (p != null) addBlock({'t': 'aud', 'p': p});
      setState(() {});
      return;
    }
    if (!await rec.hasPermission()) { msg('Autorisez le micro'); return; }
    final d = await getApplicationDocumentsDirectory();
    await rec.start(const RecordConfig(), path: '${d.path}/${DateTime.now().millisecondsSinceEpoch}.m4a');
    recing = true;
    setState(() {});
    msg('Enregistrement… touchez le micro pour arrêter');
  }

  void imgSheet(Map<String, dynamic> b) => showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (c, ss) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [const Text('Taille'), Expanded(child: Slider(value: b['w'], min: .2, max: 1, onChanged: (v) { ss(() => b['w'] = v); setState(() {}); }))]),
                Row(children: [const Text('Coins'), Expanded(child: Slider(value: b['r'], min: 0, max: 60, onChanged: (v) { ss(() => b['r'] = v); setState(() {}); }))]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton(onPressed: () { ss(() => b['b'] = !(b['b'] == true)); setState(() {}); }, child: const Text('Bordure')),
                  TextButton(onPressed: () { final i = bl.indexOf(b); bl.removeAt(i); cs.removeAt(i); act = bl.indexWhere((x) => x['t'] == 'text'); Navigator.pop(c); setState(() {}); }, child: const Text('Supprimer')),
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
                ]),
              ]))));

  @override
  void dispose() { sp.stop(); rec.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext c) {
    final d = DateTime.fromMillisecondsSinceEpoch(widget.n['t']);
    String z(int x) => x.toString().padLeft(2, '0');
    return PopScope(
      onPopInvokedWithResult: (_, __) => commit(),
      child: Scaffold(
        appBar: AppBar(backgroundColor: Colors.black, title: const Text('Notes'), actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: () { FocusScope.of(c).unfocus(); commit(); }),
        ]),
        body: Column(children: [
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 18),
            label: Text((widget.n['folder'] ?? '') == '' ? 'Sans nom' : widget.n['folder']),
            onPressed: () async { final f = await choose(c, 'Dossier', ['Sans nom', ...folders]); if (f != null) setState(() => widget.n['folder'] = f == 'Sans nom' ? '' : f); }))),
          Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 0), child: TextField(controller: title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600), decoration: const InputDecoration(border: InputBorder.none, hintText: 'Titre'))),
          Padding(padding: const EdgeInsets.only(left: 24, bottom: 8), child: Align(alignment: Alignment.centerLeft, child: Text('${z(d.day)}/${z(d.month)}/${d.year}, ${z(d.hour)}:${z(d.minute)}', style: const TextStyle(color: Colors.grey)))),
          Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 24), itemCount: bl.length, itemBuilder: (_, i) {
            final b = bl[i];
            if (b['t'] == 'text') return Focus(onFocusChange: (f) { if (f) act = i; }, child: TextField(controller: cs[i], maxLines: null, style: const TextStyle(fontSize: 20, height: 1.5), decoration: InputDecoration(border: InputBorder.none, hintText: bl.length == 1 ? 'Écrivez ici…' : null)));
            if (b['t'] == 'aud') return AudioTile(b['p']);
            return GestureDetector(onTap: () => imgSheet(b), child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: b['w'], child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8), clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(b['r']), border: b['b'] == true ? Border.all(color: green, width: 3) : null),
              child: Image.file(File(b['p']))))));
          })),
          if (live.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(live, style: const TextStyle(color: Colors.grey))),
          Container(color: const Color(0xFF0C0C0C), padding: const EdgeInsets.symmetric(vertical: 8), child: SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            IconButton(icon: const Icon(Icons.image_outlined, size: 30), onPressed: pickImage),
            IconButton(icon: Icon(Icons.mic_none, size: 30, color: recing ? Colors.red : null), onPressed: toggleRec),
            IconButton(icon: Stack(clipBehavior: Clip.none, children: [Icon(Icons.mic_none, size: 30, color: dic ? green : null), Positioned(right: -6, bottom: -4, child: Icon(Icons.edit, size: 14, color: dic ? green : null))]), onPressed: toggleDic),
            IconButton(icon: const Icon(Icons.check_circle_outline, size: 30), onPressed: () { final c0 = cs[act]!; final i = c0.selection.isValid ? c0.selection.end : c0.text.length; c0.value = TextEditingValue(text: '${c0.text.substring(0, i)}☐ ${c0.text.substring(i)}', selection: TextSelection.collapsed(offset: i + 2)); }),
          ]))),
        ]),
      ),
    );
  }
}
