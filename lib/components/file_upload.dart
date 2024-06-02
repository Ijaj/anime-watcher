import 'dart:io';
import 'package:anime_watcher/controllers/ItemController.dart';
import 'package:anime_watcher/utilities/utilities.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/Item.dart';

class ItemOption{
  String title;
  int id;

  ItemOption({required this.id, required this.title});
}

class FileUploadDialog extends StatefulWidget {
  final void Function(String file)? onFileSelected;
  final BuildContext context;
  const FileUploadDialog({super.key, this.onFileSelected, required this.context});

  @override
  _FileUploadDialogState createState() => _FileUploadDialogState();
}

class _FileUploadDialogState extends State<FileUploadDialog> {
  String _selectedDir = '';
  late Directory rootDir;
  ExtractionResult? _result;
  Type _type = Type.anime;

  List<ItemOption> _options = [];
  ItemOption? _selectedItem;

  final TextEditingController _pathController = TextEditingController();
  final TextStyle ts = const TextStyle(fontSize: 22);
  final TextEditingController _selectController = TextEditingController();

  Future<void> setRootDir() async {
    rootDir = await getApplicationDocumentsDirectory();
  }

  void updatePath(){
    doParsing(_pathController.text);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select Root Folder', lockParentWindow: true, initialDirectory: rootDir.path);
    if (result != null) {
      _pathController.value = TextEditingValue(text: result);
      setState(() {
        _selectedDir = result;
      });
      // call the title parse function
      doParsing(result);
    }
  }

  // title parse function
  void doParsing(String value) {
    if(value.isEmpty) {
      setState(() {
        _result = ExtractionResult(title: '', seasons: []);
      });
    }
    String separator = Platform.isWindows ? '\\' : '/';
    String selectedFolder = value.split(separator).last;
    ExtractionResult result = TitleExtractor.extractTitleAndSeasonFromFolderName(selectedFolder);
    if (kDebugMode) {
      print(selectedFolder);
    }
    setState(() {
      _result = result;
    });
  }

  void fetchAndParse() async {
    if(_result == null) return;
    if(_type == Type.anime){
      List<dynamic> animeMatches = await Anime.searchAnime(_result!.title);

      if(animeMatches.isEmpty) return;

      List<ItemOption> temp = [];
      for(int i = 0; i < animeMatches.length; i++){
        int id = animeMatches[i]['node']['id'];
        String title = animeMatches[i]['node']['title'];
        ItemOption item = ItemOption(id: id, title: title);
        temp.add(item);
      }
      setState(() {
        _options.clear();
        _options = temp;
        _selectedItem = temp[0];
      });
    }
  }

  void addToLibrary() async {
    if(_selectedDir.isEmpty) return;

    if(_result!.seasons.isNotEmpty){
      Map<int, String> seasons = await TitleExtractor.getSeasonsInsideFolder(_selectedDir);
      // if 0 paths, then it is an isolated season download
      dynamic r = Anime.getAnimeDetails(_selectedItem!.id);
      Item item = Item.parse(r: r, selectedDir: _selectedDir, id: _selectedItem?.id, type: _type, seasons: seasons);
      bool created = await ItemController.create(item);
    }
  }

  @override
  void initState() {
    setState(() {
      setRootDir();
    });
    _pathController.addListener(updatePath);
    super.initState();
  }

  @override
  void dispose() {
    _pathController.removeListener(updatePath);
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (var element in _options) {print(element.id);}
    print(_selectedItem?.id);
    return Dialog(
      backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(.9),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Form(
                      child: TextField(
                        onSubmitted: doParsing,
                        // onChanged: doParsing,
                        controller: _pathController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          // fillColor: Theme.of(context).secondaryHeaderColor,
                          label: Text('Select A Folder'),
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                      onPressed: _pickFile,
                      style: ElevatedButton.styleFrom(
                        fixedSize: const Size(200, 40),
                      ),
                      child: const Text('Select a Root Folder')
                  ),
                  // TextField(),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            SizedBox(
              height: 40,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: Text(_result != null ? _result!.title : 'Selected Folder', textAlign: TextAlign.right, style: ts),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton(
                    showSelectedIcon: true,
                    segments: const <ButtonSegment<Type>>[
                      ButtonSegment(value: Type.anime, label: Text('Anime'), icon: Icon(Icons.animation)),
                      ButtonSegment(value: Type.movie, label: Text('Movie'), icon: Icon(Icons.movie)),
                      ButtonSegment(value: Type.series, label: Text('TV Series'), icon: Icon(Icons.tv)),
                    ],
                    selected: <Type>{_type},
                    onSelectionChanged: (Set<Type> newValue){
                      setState(() {
                        _type = newValue.first;
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 200,
                    height: 40,
                    child: ElevatedButton(onPressed: _result != null ? fetchAndParse : null, child: const Text('Parse And Fetch'))
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: Text(_options.length > 1 ? 'Found more than 1 anime, Select the one you want' : '', textAlign: TextAlign.right, style: ts),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownMenu<ItemOption>(
                    enabled: _options.isNotEmpty,
                    width: 340,
                    controller: _selectController,
                    label: const Text('Select One'),
                    onSelected: (ItemOption? value){
                      _selectedItem = value;
                    },
                    dropdownMenuEntries: _options.map((e) => DropdownMenuEntry<ItemOption>(
                        value: e,
                        label: e.title
                    )).toList(growable: false),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                      width: 200,
                      height: 40,
                      child: ElevatedButton(onPressed: _options.isNotEmpty ? addToLibrary : null, child: const Text('Add To Library'))
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            Expanded(
              child: SizedBox(
                width: 500,
                child: Table(
                  border: TableBorder.all(color: Colors.white),
                  children: [
                    /// NAME
                    TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('Name', style: ts),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('__Name__', style: ts),
                          ),
                        ]
                    ),
                    /// TYPE
                    TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('Type', style: ts),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('__Type__', style: ts),
                          ),
                        ]
                    ),
                    /// Genre
                    TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('Genre', style: ts),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('__Genre__', style: ts),
                          ),
                        ]
                    ),
                    /// Seasons released
                    TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('Seasons Released', style: ts),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('__Seasons__', style: ts),
                          ),
                        ]
                    ),
                    /// Seasons On Disk
                    TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text('Seasons On Disk', style: ts),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 7, 0, 7),
                            child: Text(_result != null ? _result!.seasons.join(', ') : '', style: ts),
                          ),
                        ]
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8.0),
                ElevatedButton(
                  onPressed: () => (){
                    widget.onFileSelected?.call(_selectedDir);
                    Navigator.of(context).pop(_selectedDir);
                  },
                  child: const Text('Upload'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}