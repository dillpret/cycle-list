import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart'; // For clipboard access

/// A simple Note model with text and a timestamp.
class Note {
  String text;
  DateTime timestamp;
  Note({required this.text, required this.timestamp});

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      text: json['text'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// An item model that holds a title and a list of notes.
class ListItem {
  String id;
  String title;
  List<Note> notes;

  ListItem({required this.id, required this.title, List<Note>? notes})
      : notes = notes ?? [];

  factory ListItem.fromJson(Map<String, dynamic> json) {
    return ListItem(
      id: json['id'],
      title: json['title'],
      notes: json['notes'] != null
          ? (json['notes'] as List).map((e) => Note.fromJson(e)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes.map((note) => note.toJson()).toList(),
      };
}

void main() => runApp(MyApp());

/// The root widget of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoopNotes',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(),
    );
  }
}

/// The main page holding the list state and two modes: View and Manage.
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

/// State for MyHomePage.
///
/// Maintains:
/// - [_items]: the list of items (each with its own notes)
/// - [_activeIndex]: the index of the currently active item
/// - [_currentTabIndex]: 0 for "View" mode, 1 for "Manage" mode
/// - Data is persisted either to a local file (mobile) or to SharedPreferences (web).
class _MyHomePageState extends State<MyHomePage> {
  int _currentTabIndex = 0; // 0: View mode, 1: Manage mode
  List<ListItem> _items = [];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /////////// Persistence Methods ///////////

Future<String?> _showImportChoiceDialog() async {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Import Data"),
        content: const Text("Choose how you want to import your data."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, "file"),
            child: const Text("From File"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "clipboard"),
            child: const Text("From Clipboard"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancel"),
          ),
        ],
      );
    },
  );
}

/// Imports LoopNotes data from a file or clipboard.
Future<void> _importData() async {
  try {
    // Ask the user whether they want to import from a file or clipboard
    String? choice = await _showImportChoiceDialog();
    if (choice == null) return; // User canceled

    String jsonData = "";

    if (choice == "file") {
      // Pick a JSON file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        jsonData = await file.readAsString();
      }
    } else if (choice == "clipboard") {
      // Get JSON data from clipboard
      ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null) {
        jsonData = clipboardData.text!;
      }
    }

    if (jsonData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No valid data found to import.")),
      );
      return;
    }

    // Parse the JSON and update the app state
    Map<String, dynamic> data = jsonDecode(jsonData);
    List<ListItem> importedItems = (data["items"] as List)
        .map((itemJson) => ListItem.fromJson(itemJson))
        .toList();
    int importedIndex = data["activeIndex"] ?? 0;

    // Update the state
    setState(() {
      _items = importedItems;
      _activeIndex = (importedIndex >= 0 && importedIndex < _items.length)
          ? importedIndex
          : 0;
    });

    // Save the imported data
    await _saveData();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Import successful!")),
    );
  } catch (e) {
    print("Error importing data: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to import data.")),
    );
  }
}

  /// Returns the local file used for data persistence (mobile only).
  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/loopnotes_data.json');
  }

  /// Loads the saved data as a JSON string.
  Future<String?> _loadDataString() async {
    if (kIsWeb) {
      // On web, use SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString("loopnotes_data");
    } else {
      // On mobile/desktop, use a local file.
      try {
        final file = await _getLocalFile();
        if (await file.exists()) {
          return await file.readAsString();
        }
      } catch (e) {
        print("Error loading file data: $e");
      }
      return null;
    }
  }

  /// Saves the given JSON string.
  Future<void> _saveDataString(String data) async {
    if (kIsWeb) {
      // On web, save using SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("loopnotes_data", data);
    } else {
      // On mobile/desktop, save to a local file.
      final file = await _getLocalFile();
      await file.writeAsString(data);
    }
  }

  /// Exports and shares the LoopNotes data.
Future<void> _exportData() async {
  try {
    // Convert items to a JSON string
    Map<String, dynamic> data = {
      "activeIndex": _activeIndex,
      "items": _items.map((item) => item.toJson()).toList(),
    };
    String jsonData = jsonEncode(data);

    // Share the JSON data
    await Share.share(jsonData, subject: "Exported LoopNotes Data");

  } catch (e) {
    print("Error exporting data: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to export data."))
    );
  }
}

  /// Loads the list items (with notes) and active index.
  Future<void> _loadData() async {
    String? contents = await _loadDataString();
    if (contents != null && contents.isNotEmpty) {
      try {
        final Map<String, dynamic> data = jsonDecode(contents);
        setState(() {
          _activeIndex = data["activeIndex"] ?? 0;
          _items = (data["items"] as List)
              .map((itemJson) => ListItem.fromJson(itemJson))
              .toList();
        });
        return;
      } catch (e) {
        print("Error decoding data: $e");
      }
    }
    // If no saved data, initialize with a default list.
    setState(() {
      _items = [
        ListItem(id: '1', title: 'Item 1'),
        ListItem(id: '2', title: 'Item 2'),
        ListItem(id: '3', title: 'Item 3'),
      ];
      _activeIndex = 0;
    });
  }

  /// Saves the current list (including notes) and active index.
  Future<void> _saveData() async {
    Map<String, dynamic> data = {
      "activeIndex": _activeIndex,
      "items": _items.map((item) => item.toJson()).toList(),
    };
    String jsonData = jsonEncode(data);
    await _saveDataString(jsonData);
  }

  /////////// End Persistence Methods ///////////

  /// Cycles to the next item (in circular fashion) and saves the new active index.
  void _cycleNext() {
    if (_items.isEmpty) return;
    setState(() {
      _activeIndex = (_activeIndex + 1) % _items.length;
    });
    _saveData();
  }

  /// Cycles to the previous item (in circular fashion) and saves the new active index.
  void _cyclePrevious() {
    if (_items.isEmpty) return;
    setState(() {
      _activeIndex = (_activeIndex - 1 + _items.length) % _items.length;
    });
    _saveData();
  }

  /// Adds a new item to the list.
  void _addItem(String newTitle) {
    setState(() {
      _items.add(ListItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: newTitle));
      // If the list was empty, reset the active index to the first item.
      if (_items.length == 1) {
        _activeIndex = 0;
      }
    });
    _saveData();
  }

  /// Removes an item from the list.
  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      // Adjust the active index if needed.
      if (_activeIndex >= _items.length) {
        _activeIndex = 0;
      }
    });
    _saveData();
  }

  /// Edits an item in the list.
  void _editItem(int index, String newTitle) {
    setState(() {
      _items[index].title = newTitle;
    });
    _saveData();
  }

  /// Reorders items in the list and adjusts the active index accordingly.
  void _reorderItem(int oldIndex, int newIndex) {
  setState(() {
    if (newIndex > oldIndex) {
      newIndex--;  // Adjust because items shift when removed
    }
    
    final movedItem = _items.removeAt(oldIndex);
    _items.insert(newIndex, movedItem);

    // Update _activeIndex to maintain the same item in View Mode
    if (_activeIndex == oldIndex) {
      _activeIndex = newIndex;
    } else if (oldIndex < _activeIndex && _activeIndex <= newIndex) {
      _activeIndex--;  // Shift active index down if necessary
    } else if (newIndex <= _activeIndex && _activeIndex < oldIndex) {
      _activeIndex++;  // Shift active index up if necessary
    }
  });

  _saveData();  // Save the updated order
}

  /// Displays a dialog to add a new item.
  Future<void> _showAddItemDialog() async {
    String newTitle = '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Item"),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: "Enter item title"),
            onChanged: (value) {
              newTitle = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (newTitle.trim().isNotEmpty) {
                  _addItem(newTitle.trim());
                }
                Navigator.of(context).pop();
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  /// Displays a dialog to edit an existing item.
  Future<void> _showEditItemDialog(int index) async {
    String editedTitle = _items[index].title;
    TextEditingController controller =
        TextEditingController(text: editedTitle);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Item"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Enter new title"),
            onChanged: (value) {
              editedTitle = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (editedTitle.trim().isNotEmpty) {
                  _editItem(index, editedTitle.trim());
                }
                Navigator.of(context).pop();
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  /// Displays a dialog to add a new note to the active item.
  Future<void> _showAddNoteDialog() async {
    String noteText = '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Note"),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: "Enter note text"),
            onChanged: (value) {
              noteText = value;
            },
            // Allow multiple lines of input.
            keyboardType: TextInputType.multiline,
            maxLines: null,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (noteText.trim().isNotEmpty) {
                  _addNoteToActiveItem(noteText.trim());
                }
                Navigator.of(context).pop();
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  /// Adds a note (with the current time) to the currently active item.
  void _addNoteToActiveItem(String noteText) {
    if (_items.isEmpty) return;
    setState(() {
      final note = Note(text: noteText, timestamp: DateTime.now());
      // Insert at the beginning so that the newest note is first.
      _items[_activeIndex].notes.insert(0, note);
    });
    _saveData();
  }

  /// Deletes a note from the currently active item.
  void _deleteNoteFromActiveItem(int noteIndex) {
    setState(() {
      _items[_activeIndex].notes.removeAt(noteIndex);
    });
    _saveData();
  }

  /// Builds the View mode screen.
  Widget _buildViewScreen() {
    if (_items.isEmpty) {
      return const Center(
        child: Text("No items available. Please add items in manage mode."),
      );
    }
    final currentItem = _items[_activeIndex];
    return Column(
      children: [
        // Active item display and navigation buttons.
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                currentItem.title,
                style: const TextStyle(fontSize: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _cyclePrevious,
                    child: const Text("Previous"),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: _cycleNext,
                    child: const Text("Next"),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        // Notes header and "Add Note" button.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Notes", style: TextStyle(fontSize: 20)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _showAddNoteDialog,
              ),
            ],
          ),
        ),
        // Expanded list of notes.
        Expanded(
          child: currentItem.notes.isEmpty
              ? const Center(child: Text("No notes yet."))
              : ListView.builder(
                  itemCount: currentItem.notes.length,
                  itemBuilder: (context, index) {
                    final note = currentItem.notes[index];
                    return ListTile(
                      title: Text(
                        note.text,
                        softWrap: true,
                      ),
                      subtitle: Text("${note.timestamp.toLocal()}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteNoteFromActiveItem(index),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Builds the Manage mode screen with a reorderable list.
  Widget _buildManageScreen() {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _exportData,
              icon: const Icon(Icons.share),
              label: const Text("Export"),
            ),
            ElevatedButton.icon(
              onPressed: _importData,
              icon: const Icon(Icons.upload_file),
              label: const Text("Import"),
            ),
          ],
        ),
      ),
      Expanded(
        child: _items.isEmpty
            ? const Center(child: Text("No items. Add some using the button below."))
            : ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  _reorderItem(oldIndex, newIndex);
                },
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (int index = 0; index < _items.length; index++)
                    Card(
                      key: ValueKey(_items[index].id),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text(_items[index].title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditItemDialog(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removeItem(index),
                            ),
                            const Icon(Icons.drag_handle),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LoopNotes"),
      ),
      body: _currentTabIndex == 0 ? _buildViewScreen() : _buildManageScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.visibility), label: "View"),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: "Manage"),
        ],
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
      ),
      floatingActionButton: _currentTabIndex == 1
          ? FloatingActionButton(
              onPressed: _showAddItemDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
