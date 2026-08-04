/// Memory Search Page - compact layout

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/memory_result.dart';
import '../process/process_selector.dart';

/// Search types
enum SearchType { exact, fuzzy, range, aob }

/// Current search type provider
final searchTypeProvider = StateProvider<SearchType>((ref) => SearchType.exact);

/// Search results provider
final searchResultsProvider = StateProvider<List<MemoryResult>>((ref) => []);

/// Data type provider
final dataTypeProvider = StateProvider<DataType>((ref) => DataType.dword);

/// Controls collapsed provider
final controlsCollapsedProvider = StateProvider<bool>((ref) => false);

/// Memory search page
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _minController = TextEditingController();
  final TextEditingController _maxController = TextEditingController();
  String _selectedFuzzyComparison = 'changed';

  @override
  void dispose() {
    _valueController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final attachedProcess = ref.read(attachedProcessProvider);
    if (attachedProcess == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please attach to a game process first')),
      );
      return;
    }

    final searchType = ref.read(searchTypeProvider);
    final dataType = ref.read(dataTypeProvider);

    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      ref.read(searchResultsProvider.notifier).state = [];

      List<dynamic>? rawResults;

      switch (searchType) {
        case SearchType.range:
          final min = int.tryParse(_minController.text);
          final max = int.tryParse(_maxController.text);
          if (min == null || max == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a valid range')),
            );
            return;
          }
          rawResults = await channel.invokeMethod('searchByRange', {
            'minValue': min,
            'maxValue': max,
            'type': dataType.name,
          }) as List<dynamic>?;

        case SearchType.fuzzy:
          rawResults = await channel.invokeMethod('searchFuzzy', {
            'comparison': _selectedFuzzyComparison,
            'type': dataType.name,
          }) as List<dynamic>?;

        case SearchType.aob:
          final pattern = _valueController.text.trim();
          if (pattern.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter an AOB pattern')),
            );
            return;
          }
          rawResults = await channel.invokeMethod('searchAob', {
            'pattern': pattern,
          }) as List<dynamic>?;

        case SearchType.exact:
          final value = _valueController.text.trim();
          if (value.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a search value')),
            );
            return;
          }

          dynamic searchValue;
          switch (dataType) {
            case DataType.float:
            case DataType.double:
              searchValue = double.tryParse(value);
              break;
            default:
              searchValue = int.tryParse(value);
              break;
          }

          if (searchValue == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a valid value')),
            );
            return;
          }

          rawResults = await channel.invokeMethod('searchExact', {
            'value': searchValue,
            'type': dataType.name,
          }) as List<dynamic>?;
      }

      if (rawResults != null) {
        final results = rawResults.map((item) {
          return MemoryResult.fromJson(Map<String, dynamic>.from(item as Map));
        }).toList();

        ref.read(searchResultsProvider.notifier).state = results;
        // Auto-collapse controls when results exist
        if (results.isNotEmpty) {
          ref.read(controlsCollapsedProvider.notifier).state = true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${results.length} results'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  Future<void> _writeMemory(MemoryResult result, dynamic newValue) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final success = await channel.invokeMethod('writeMemory', {
        'address': result.addressInt,
        'value': newValue,
        'type': result.type.name,
      });
      if (success == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Set ${result.address} = $newValue')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Write failed: $e')),
      );
    }
  }

  Future<void> _freezeMemory(MemoryResult result, dynamic value) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final success = await channel.invokeMethod('freezeMemory', {
        'address': result.addressInt,
        'value': value,
        'type': result.type.name,
      });
      if (success == true) {
        final results = ref.read(searchResultsProvider);
        ref.read(searchResultsProvider.notifier).state = results.map((r) {
          if (r.addressInt == result.addressInt) {
            return r.copyWith(isFrozen: true, frozenValue: value);
          }
          return r;
        }).toList();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Frozen ${result.address} = $value')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Freeze failed: $e')),
      );
    }
  }

  Future<void> _unfreezeMemory(MemoryResult result) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      await channel.invokeMethod('unfreezeMemory', {
        'address': result.addressInt,
      });
      final results = ref.read(searchResultsProvider);
      ref.read(searchResultsProvider.notifier).state = results.map((r) {
        if (r.addressInt == result.addressInt) {
          return r.copyWith(isFrozen: false);
        }
        return r;
      }).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unfrozen ${result.address}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unfreeze failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchType = ref.watch(searchTypeProvider);
    final dataType = ref.watch(dataTypeProvider);
    final results = ref.watch(searchResultsProvider);
    final attachedProcess = ref.watch(attachedProcessProvider);
    final collapsed = ref.watch(controlsCollapsedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Search'),
        actions: [
          // Collapse/expand button
          if (results.isNotEmpty)
            IconButton(
              icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              onPressed: () {
                ref.read(controlsCollapsedProvider.notifier).state = !collapsed;
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Top bar: process status + search type + data type
          _buildTopBar(attachedProcess, searchType, dataType, collapsed),
          // Search input area (collapsible)
          if (!collapsed) _buildSearchInput(searchType, dataType),
          // Result bar + quick search when collapsed
          if (results.isNotEmpty) _buildResultBar(results, collapsed, searchType, dataType),
          // Results list
          Expanded(
            child: results.isEmpty
                ? _buildEmptyState(attachedProcess)
                : _buildResultList(results),
          ),
        ],
      ),
    );
  }

  /// Top bar: process status + search type + data type
  Widget _buildTopBar(
    dynamic attachedProcess,
    SearchType searchType,
    DataType dataType,
    bool collapsed,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFFDFBF7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // First row: process status
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProcessSelectorPage()),
              );
            },
            child: Row(
              children: [
                Icon(
                  attachedProcess != null ? Icons.check_circle : Icons.circle,
                  size: 10,
                  color: attachedProcess != null ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    attachedProcess != null
                        ? '${attachedProcess.packageName} (PID:${attachedProcess.pid})'
                        : 'No process attached - tap to select',
                    style: TextStyle(
                      color: attachedProcess != null ? Colors.green : Color(0xFFA1887F),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (attachedProcess != null)
                  const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFFA1887F)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Second row: search type + data type + search/reset
          Row(
            children: [
              // Search type chips
              ...SearchType.values.map((type) {
                final isSelected = type == searchType;
                final labels = {
                  SearchType.exact: 'Exact',
                  SearchType.fuzzy: 'Fuzzy',
                  SearchType.range: 'Range',
                  SearchType.aob: 'AOB',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(labels[type]!, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(searchTypeProvider.notifier).state = type;
                    },
                    selectedColor: const Color(0xFF8D6E63),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }),
              const Spacer(),
              // Data type dropdown
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DataType>(
                    value: dataType,
                    isDense: true,
                    dropdownColor: const Color(0xFFFFF9F0),
                    style: const TextStyle(
                      color: Color(0xFF8D6E63),
                      fontSize: 12,
                    ),
                    items: DataType.values
                        .where((t) => t != DataType.string)
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            ))
                        .toList(),
                    onChanged: (type) {
                      if (type != null) {
                        ref.read(dataTypeProvider.notifier).state = type;
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Search input area
  Widget _buildSearchInput(SearchType searchType, DataType dataType) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      color: const Color(0xFFFFF9F0),
      child: _buildInputByType(searchType),
    );
  }

  Widget _buildInputByType(SearchType searchType) {
    switch (searchType) {
      case SearchType.range:
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minController,
                decoration: const InputDecoration(
                  hintText: 'Min',
                  prefixIcon: Icon(Icons.arrow_downward, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~', style: TextStyle(color: Color(0xFFA1887F))),
            ),
            Expanded(
              child: TextField(
                controller: _maxController,
                decoration: const InputDecoration(
                  hintText: 'Max',
                  prefixIcon: Icon(Icons.arrow_upward, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            _buildSearchResetButtons(),
          ],
        );

      case SearchType.fuzzy:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _fuzzyChip('changed', 'Changed'),
                _fuzzyChip('unchanged', 'Unchanged'),
                _fuzzyChip('increased', 'Increased'),
                _fuzzyChip('decreased', 'Decreased'),
                _fuzzyChip('greater', 'Greater'),
                _fuzzyChip('less', 'Less'),
                _fuzzyChip('equal', 'Equal'),
                _fuzzyChip('not_equal', 'Not Equal'),
              ],
            ),
            const SizedBox(height: 8),
            _buildSearchResetButtons(),
          ],
        );

      case SearchType.aob:
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _valueController,
                decoration: const InputDecoration(
                  hintText: 'AOB pattern (e.g.: 48 89 5C 24 ? 48)',
                  prefixIcon: Icon(Icons.fingerprint, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.text,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            _buildSearchResetButtons(),
          ],
        );

      case SearchType.exact:
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _valueController,
                decoration: const InputDecoration(
                  hintText: 'Enter value',
                  prefixIcon: Icon(Icons.numbers, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            _buildSearchResetButtons(),
          ],
        );
    }
  }

  /// Search + Reset buttons
  Widget _buildSearchResetButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: _performSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8D6E63),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            onPressed: () {
              ref.read(searchResultsProvider.notifier).state = [];
              _valueController.clear();
              _minController.clear();
              _maxController.clear();
              ref.read(controlsCollapsedProvider.notifier).state = false;
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Icon(Icons.refresh, size: 18, color: Color(0xFFA1887F)),
          ),
        ),
      ],
    );
  }

  /// Fuzzy search chip
  Widget _fuzzyChip(String value, String label) {
    final isSelected = _selectedFuzzyComparison == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFuzzyComparison = value;
        });
      },
      selectedColor: const Color(0xFF8D6E63),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  /// Result bar (shows quick search when collapsed)
  Widget _buildResultBar(
    List<MemoryResult> results,
    bool collapsed,
    SearchType searchType,
    DataType dataType,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFFDFBF7),
      child: Row(
        children: [
          const Icon(Icons.list_alt, size: 16, color: Color(0xFF8D6E63)),
          const SizedBox(width: 6),
          Text(
            '${results.length} results',
            style: const TextStyle(color: Color(0xFF3E2723), fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (results.length > 100)
            const Text(
              ' (showing first 100)',
              style: TextStyle(color: Color(0xFFA1887F), fontSize: 11),
            ),
          const Spacer(),
          // Quick search when collapsed
          if (collapsed) ...[
            SizedBox(
              height: 28,
              child: ElevatedButton.icon(
                onPressed: _performSearch,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: () {
                  ref.read(controlsCollapsedProvider.notifier).state = false;
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Icon(Icons.tune, size: 16, color: Color(0xFFA1887F)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Empty state
  Widget _buildEmptyState(dynamic attachedProcess) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            attachedProcess == null ? Icons.link_off : Icons.search_off,
            size: 48,
            color: Color(0xFFA1887F),
          ),
          const SizedBox(height: 12),
          Text(
            attachedProcess == null ? 'Please attach to a game process' : 'Enter a value to start searching',
            style: const TextStyle(color: Color(0xFFA1887F), fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Result list
  Widget _buildResultList(List<MemoryResult> results) {
    final displayResults = results.length > 100
        ? results.sublist(0, 100)
        : results;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: displayResults.length,
      itemBuilder: (context, index) {
        return _buildCompactResultItem(displayResults[index]);
      },
    );
  }

  /// Compact result item
  Widget _buildCompactResultItem(MemoryResult result) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: const Color(0xFFFDFBF7),
      child: InkWell(
        onTap: () => _showEditDialog(result),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Status icon
              Icon(
                result.isFrozen ? Icons.lock : Icons.memory,
                color: result.isFrozen
                    ? const Color(0xFF6D4C41)
                    : result.isFavorite
                        ? Colors.amber
                        : Color(0xFFA1887F),
                size: 18,
              ),
              const SizedBox(width: 10),
              // Address
              Expanded(
                flex: 3,
                child: Text(
                  result.address,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF8D6E63),
                  ),
                ),
              ),
              // Value
              Expanded(
                flex: 2,
                child: Text(
                  '${result.value}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              // Type label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.type.displayName,
                  style: const TextStyle(fontSize: 10, color: Color(0xFFA1887F)),
                ),
              ),
              const SizedBox(width: 4),
              // Actions
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _showEditDialog(result);
                      break;
                    case 'freeze':
                      if (result.isFrozen) {
                        _unfreezeMemory(result);
                      } else {
                        _showFreezeDialog(result);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit value')),
                  PopupMenuItem(
                    value: 'freeze',
                    child: Text(result.isFrozen ? 'Unfreeze' : 'Freeze'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(MemoryResult result) {
    final controller = TextEditingController(text: result.value.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFF9F0),
        title: const Text('Edit memory value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Address: ${result.address}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF8D6E63),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New value',
                hintText: 'Enter the value to set',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newValue = controller.text.trim();
              if (newValue.isNotEmpty) {
                dynamic value;
                switch (result.type) {
                  case DataType.float:
                  case DataType.double:
                    value = double.tryParse(newValue);
                    break;
                  default:
                    value = int.tryParse(newValue);
                    break;
                }
                if (value != null) {
                  _writeMemory(result, value);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showFreezeDialog(MemoryResult result) {
    final controller = TextEditingController(text: result.value.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFF9F0),
        title: const Text('Freeze memory value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Address: ${result.address}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF8D6E63),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Freeze value',
                hintText: 'Enter the value to freeze',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final freezeValue = controller.text.trim();
              if (freezeValue.isNotEmpty) {
                dynamic value;
                switch (result.type) {
                  case DataType.float:
                  case DataType.double:
                    value = double.tryParse(freezeValue);
                    break;
                  default:
                    value = int.tryParse(freezeValue);
                    break;
                }
                if (value != null) {
                  _freezeMemory(result, value);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Freeze'),
          ),
        ],
      ),
    );
  }
