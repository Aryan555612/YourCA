import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/categories/categorization_service.dart';

class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  List<List<dynamic>> _rawRows = [];
  List<_ParsedRow> _parsedRows = [];
  Map<String, int> _columnMap = {};
  bool _isParsing = false;
  bool _isImporting = false;
  String? _fileName;
  String? _error;
  int _importedCount = 0;

  // Column mapping keys
  static const _kDate = 'date';
  static const _kNarration = 'narration';
  static const _kDebit = 'debit';
  static const _kCredit = 'credit';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isParsing = true;
      _error = null;
      _parsedRows = [];
    });

    try {
      final bytes = result.files.first.bytes;
      final content = bytes != null
          ? String.fromCharCodes(bytes)
          : File(result.files.first.path!).readAsStringSync();

      final rows = const CsvToListConverter(eol: '\n').convert(content);
      if (rows.isEmpty) {
        setState(() {
          _error = 'CSV file is empty';
          _isParsing = false;
        });
        return;
      }

      setState(() {
        _rawRows = rows;
        _fileName = result.files.first.name;
        _columnMap = _autoDetectColumns(rows[0]);
        _parsedRows = _parseRows(rows);
        _isParsing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to parse CSV: $e';
        _isParsing = false;
      });
    }
  }

  Map<String, int> _autoDetectColumns(List<dynamic> header) {
    final map = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final h = header[i].toString().toLowerCase().trim();
      if (h.contains('date')) map[_kDate] = i;
      if (h.contains('narr') || h.contains('desc') || h.contains('detail')) {
        map[_kNarration] = i;
      }
      if (h.contains('debit') || h.contains('withdrawal') ||
          h.contains('dr')) {
        map[_kDebit] = i;
      }
      if (h.contains('credit') || h.contains('deposit') || h.contains('cr')) {
        map[_kCredit] = i;
      }
    }
    return map;
  }

  List<_ParsedRow> _parseRows(List<List<dynamic>> rows) {
    final result = <_ParsedRow>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) {
        continue;
      }

      try {
        final dateStr = _columnMap.containsKey(_kDate)
            ? row[_columnMap[_kDate]!].toString().trim()
            : '';
        final narration = _columnMap.containsKey(_kNarration)
            ? row[_columnMap[_kNarration]!].toString().trim()
            : '';
        final debitStr = _columnMap.containsKey(_kDebit)
            ? row[_columnMap[_kDebit]!].toString().trim()
            : '';
        final creditStr = _columnMap.containsKey(_kCredit)
            ? row[_columnMap[_kCredit]!].toString().trim()
            : '';

        final debit = double.tryParse(debitStr.replaceAll(',', '')) ?? 0;
        final credit = double.tryParse(creditStr.replaceAll(',', '')) ?? 0;

        if (debit == 0 && credit == 0) continue;

        final amount = debit > 0 ? debit : credit;
        final type =
            debit > 0 ? TransactionType.debit : TransactionType.credit;
        final date = _parseDate(dateStr) ?? DateTime.now();
        final category =
            CategorizationService.instance.categorize(narration);

        result.add(_ParsedRow(
          date: date,
          narration: narration,
          amount: amount,
          type: type,
          category: category,
          selected: true,
        ));
      } catch (_) {
        // Skip malformed rows
      }
    }
    return result;
  }

  DateTime? _parseDate(String s) {
    // Try common formats
    final formats = [
      RegExp(r'(\d{2})[/-](\d{2})[/-](\d{4})'), // DD/MM/YYYY
      RegExp(r'(\d{4})[/-](\d{2})[/-](\d{2})'), // YYYY-MM-DD
      RegExp(r'(\d{2})[/-](\d{2})[/-](\d{2})'), // DD/MM/YY
    ];
    for (final fmt in formats) {
      final m = fmt.firstMatch(s);
      if (m != null) {
        try {
          if (s.startsWith(RegExp(r'\d{4}'))) {
            return DateTime(
                int.parse(m.group(1)!),
                int.parse(m.group(2)!),
                int.parse(m.group(3)!));
          } else {
            final year = int.parse(m.group(3)!);
            return DateTime(
                year < 100 ? 2000 + year : year,
                int.parse(m.group(2)!),
                int.parse(m.group(1)!));
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _import() async {
    final userId = ref.read(currentUserIdProvider) ?? '';
    final repo = ref.read(transactionRepositoryProvider);
    final selected = _parsedRows.where((r) => r.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _isImporting = true);

    final transactions = selected
        .map((r) => Transaction(
              id: const Uuid().v4(),
              userId: userId,
              amount: r.amount,
              type: r.type,
              category: r.category,
              merchant: r.narration,
              date: r.date,
              source: TransactionSource.statementImport,
              createdAt: DateTime.now(),
            ))
        .toList();

    await repo.addBatch(transactions);

    setState(() {
      _isImporting = false;
      _importedCount = transactions.length;
      _parsedRows = [];
      _rawRows = [];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${transactions.length} transactions'),
          backgroundColor: AppColors.credit,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Import Bank Statement')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // â”€â”€ Info banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _InfoBanner(),
          const SizedBox(height: 24),

          // â”€â”€ File picker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _FilePicker(
              fileName: _fileName,
              isParsing: _isParsing,
              onPick: _pickFile),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.debit.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.debit.withValues(alpha: 0.4)),
              ),
              child: Text(_error!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.debit)),
            ),
            const SizedBox(height: 16),
          ],

          // â”€â”€ Column mapping â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_rawRows.isNotEmpty) ...[
            _ColumnMapper(
              headers: _rawRows[0].map((h) => h.toString()).toList(),
              columnMap: _columnMap,
              onChanged: (map) {
                setState(() {
                  _columnMap = map;
                  _parsedRows = _parseRows(_rawRows);
                });
              },
            ),
            const SizedBox(height: 20),
          ],

          // â”€â”€ Preview table â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_parsedRows.isNotEmpty) ...[
            Row(
              children: [
                Text('Preview (${_parsedRows.where((r) => r.selected).length} selected)',
                    style: AppTextStyles.headlineSmall),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    for (final r in _parsedRows) r.selected = true;
                  }),
                  child: const Text('Select all'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._parsedRows.take(50).map((row) => _PreviewRow(
                  row: row,
                  onToggle: () => setState(() => row.selected = !row.selected),
                )),
            if (_parsedRows.length > 50)
              Center(
                child: Text(
                  '+ ${_parsedRows.length - 50} more rows',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isImporting ? null : _import,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(_isImporting
                  ? 'Importing...'
                  : 'Import ${_parsedRows.where((r) => r.selected).length} Transactions'),
            ),
          ],

          if (_importedCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Text('âœ…', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      '$_importedCount transactions imported!',
                      style: AppTextStyles.headlineMedium
                          .copyWith(color: AppColors.credit),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.primaryLight, size: 18),
              const SizedBox(width: 8),
              Text('How to import',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.primaryLight)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '1. Download your bank statement as CSV from net banking\n'
            '2. Pick the CSV file below\n'
            '3. Map columns if not auto-detected\n'
            '4. Review and import',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.primaryLight),
          ),
        ],
      ),
    );
  }
}

class _FilePicker extends StatelessWidget {
  final String? fileName;
  final bool isParsing;
  final VoidCallback onPick;

  const _FilePicker(
      {required this.fileName,
      required this.isParsing,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isParsing ? null : onPick,
      icon: isParsing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.upload_file_rounded),
      label: Text(fileName != null
          ? 'Change file ($fileName)'
          : 'Pick CSV file'),
    );
  }
}

class _ColumnMapper extends StatefulWidget {
  final List<String> headers;
  final Map<String, int> columnMap;
  final ValueChanged<Map<String, int>> onChanged;

  const _ColumnMapper(
      {required this.headers,
      required this.columnMap,
      required this.onChanged});

  @override
  State<_ColumnMapper> createState() => _ColumnMapperState();
}

class _ColumnMapperState extends State<_ColumnMapper> {
  late Map<String, int> _map;

  @override
  void initState() {
    super.initState();
    _map = Map.from(widget.columnMap);
  }

  @override
  Widget build(BuildContext context) {
    final colKeys = {
      'date': 'Date column',
      'narration': 'Description / Narration',
      'debit': 'Debit / Withdrawal',
      'credit': 'Credit / Deposit',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Column Mapping', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            ...colKeys.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 150,
                          child: Text(e.value, style: AppTextStyles.bodySmall)),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          value: _map[e.key],
                          dropdownColor: AppColors.surface,
                          style: AppTextStyles.bodySmall,
                          decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8)),
                          items: [
                            const DropdownMenuItem<int?>(
                                value: null, child: Text('â€” Not mapped â€”')),
                            ...widget.headers.asMap().entries.map((h) =>
                                DropdownMenuItem<int?>(
                                    value: h.key,
                                    child: Text(h.value,
                                        overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              if (val == null) {
                                _map.remove(e.key);
                              } else {
                                _map[e.key] = val;
                              }
                            });
                            widget.onChanged(_map);
                          },
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ParsedRow {
  final DateTime date;
  final String narration;
  final double amount;
  final TransactionType type;
  final String category;
  bool selected;

  _ParsedRow({
    required this.date,
    required this.narration,
    required this.amount,
    required this.type,
    required this.category,
    required this.selected,
  });
}

class _PreviewRow extends StatelessWidget {
  final _ParsedRow row;
  final VoidCallback onToggle;

  const _PreviewRow({required this.row, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDebit = row.type == TransactionType.debit;
    return Card(
      child: CheckboxListTile(
        value: row.selected,
        onChanged: (_) => onToggle(),
        activeColor: AppColors.primary,
        title: Text(
          row.narration,
          style: AppTextStyles.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${DateUtils2.toDisplayDate(row.date)}  •  ${row.category}',
          style: AppTextStyles.bodySmall,
        ),
        secondary: Text(
          '${isDebit ? '-' : '+'}${CurrencyUtils.formatNoDecimal(row.amount)}',
          style: AppTextStyles.moneySmall.copyWith(
              color: isDebit ? AppColors.debit : AppColors.credit),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}
