import 'dart:math' as math;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/item_price.dart';
import '../models/price_alert.dart';
import '../models/limit_entry.dart';
import '../services/alerts_service.dart';
import '../services/osrs_api.dart';
import '../services/price_alerts_background_service.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';
import '../utils/alchemy_profit.dart';
import '../utils/ge_tax.dart';
import '../utils/price_format.dart';
import '../widgets/skeletons.dart';
import '../widgets/updated_badge.dart';
import 'limits_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    this.currentPrice,
    this.allItems = const <ItemMapping>[],
    this.latestPrices = const <String, ItemPrice>{},
  });

  final ItemMapping item;
  final ItemPrice? currentPrice;
  final List<ItemMapping> allItems;
  final Map<String, ItemPrice> latestPrices;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with WidgetsBindingObserver {
  final OsrsApi _api = OsrsApi();
  final AlertsService _alertsService = AlertsService();
  static const String _favoriteKey = 'favorite_item_ids';
  static const Duration _timeseriesCacheTtl = Duration(minutes: 5);

  late SharedPreferences _prefs;
  late LimitService _limitService;
  List<HistoricalPricePoint> _points = <HistoricalPricePoint>[];
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _showHigh = true;
  bool _showLow = true;
  bool _autoYScale = true;
  double _manualMin = 0;
  double _manualMax = 0;
  String _selectedTimestep = '24h';
  String _chartMode = 'Lines';
  int? selectedX;
  DateTime? _timeseriesCacheAt;
  String? _errorMessage;
  List<PriceAlert> _activeItemAlerts = <PriceAlert>[];
  LimitEntry? _currentLimitEntry;
  Timer? _countdownTimer;
  final GlobalKey _chartBoundaryKey = GlobalKey();

  static const List<String> _timestepOptions = <String>[
    '5m',
    '1h',
    '6h',
    '24h',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadData();
  }

  Future<void> _initServices() async {
    _prefs = await SharedPreferences.getInstance();
    _limitService = await LimitService.create();
    await _initFavoriteState();
    _loadItemAlerts();
    _loadCurrentLimitEntry();
  }

  Future<void> _loadItemAlerts() async {
    final alerts = await _alertsService.active();
    if (!mounted) {
      return;
    }

    setState(() {
      _activeItemAlerts = alerts
          .where((alert) => alert.itemId == widget.item.id)
          .toList();
    });
  }

  Future<void> _createPriceAlert({
    required BuildContext sheetContext,
    required String direction,
    required String targetText,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final targetPrice = int.tryParse(targetText.trim());
    if (targetPrice == null || targetPrice <= 0) {
      return;
    }

    final canNotify =
        await PriceAlertsBackgroundService.requestPermissionOnFirstAlert();

    final alert = PriceAlert(
      itemId: widget.item.id,
      itemName: widget.item.name,
      targetPrice: targetPrice,
      direction: direction,
      active: true,
      createdAt: DateTime.now(),
    );
    await _alertsService.add(alert);

    if (!mounted) {
      return;
    }

    setState(() {
      _activeItemAlerts = <PriceAlert>[..._activeItemAlerts, alert];
    });
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          canNotify
              ? 'Price alert saved.'
              : 'Alert saved, but notifications are disabled.',
        ),
      ),
    );
  }

  Future<void> _removePriceAlert(PriceAlert alert) async {
    await _alertsService.remove(alert);
    if (!mounted) {
      return;
    }

    setState(() {
      _activeItemAlerts.removeWhere(
        (candidate) =>
            candidate.itemId == alert.itemId &&
            candidate.createdAt.isAtSameMomentAs(alert.createdAt),
      );
    });
  }

  Future<void> _openPriceAlertSheet() async {
    final targetController = TextEditingController();
    var direction = 'above';
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Price alerts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_activeItemAlerts.isEmpty)
                        const Text(
                          'No active alerts for this item.',
                          style: TextStyle(color: AppTheme.secondaryTextColor),
                        )
                      else
                        ..._activeItemAlerts.map(
                          (alert) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${alert.direction == 'above' ? 'Above' : 'Below'} ${PriceFormat.price(alert.targetPrice)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete alert',
                              onPressed: () async {
                                await _removePriceAlert(alert);
                                if (sheetContext.mounted) {
                                  setSheetState(() {});
                                }
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: targetController,
                        onChanged: (_) => setSheetState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Target price (gp)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(
                            value: 'above',
                            label: Text('Above'),
                          ),
                          ButtonSegment<String>(
                            value: 'below',
                            label: Text('Below'),
                          ),
                        ],
                        selected: <String>{direction},
                        onSelectionChanged: (selection) {
                          setSheetState(() {
                            direction = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              isSaving ||
                                  (int.tryParse(targetController.text) ?? 0) <=
                                      0
                              ? null
                              : () async {
                                  setSheetState(() {
                                    isSaving = true;
                                  });
                                  try {
                                    await _createPriceAlert(
                                      sheetContext: sheetContext,
                                      direction: direction,
                                      targetText: targetController.text,
                                    );
                                  } catch (_) {
                                    if (sheetContext.mounted) {
                                      setSheetState(() {
                                        isSaving = false;
                                      });
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not save the price alert.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: const Text('Set alert'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    targetController.dispose();
  }

  Future<void> _initFavoriteState() async {
    final favoriteIds = _prefs.getStringList(_favoriteKey) ?? <String>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _isFavorite = favoriteIds
          .map(int.tryParse)
          .whereType<int>()
          .contains(widget.item.id);
    });
  }

  void _loadCurrentLimitEntry() {
    _currentLimitEntry = _limitService.getActiveEntry(widget.item.id);
    if (mounted) {
      setState(() {});
    }
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentLimitEntry != null &&
          _currentLimitEntry!.isExpired(LimitService.windowDuration)) {
        _loadCurrentLimitEntry();
        return;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_timeseriesCacheAt == null ||
          now.difference(_timeseriesCacheAt!) > _timeseriesCacheTtl) {
        _loadData();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final favoriteIds = (_prefs.getStringList(_favoriteKey) ?? <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();

    if (_isFavorite) {
      favoriteIds.remove(widget.item.id);
    } else {
      favoriteIds.add(widget.item.id);
    }

    await _prefs.setStringList(
      _favoriteKey,
      favoriteIds.map((id) => id.toString()).toList(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isFavorite = !_isFavorite;
    });
  }

  Future<void> _shareChart() async {
    try {
      final boundary = _chartBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture chart')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not encode image')),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ge_chart_${widget.item.id}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final highPrice = widget.currentPrice?.high ?? 0;
      final lowPrice = widget.currentPrice?.low ?? 0;
      final text = 'GE Prices - ${widget.item.name}: High ${PriceFormat.price(highPrice)} / Low ${PriceFormat.price(lowPrice)}';

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
      );
    } catch (e) {
      if (!mounted) return;
      // On desktop or if share fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sharing available on mobile'),
          backgroundColor: AppTheme.panelColor,
        ),
      );
    }
  }

  Future<void> _openWiki() async {
    final slug = widget.item.name.trim().replaceAll(RegExp(r'\s+'), '_');
    final url = Uri.parse('https://oldschool.runescape.wiki/w/$slug');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the wiki page.')),
      );
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _autoYScale = true;
      _manualMin = 0;
      _manualMax = 0;
      selectedX = null;
    });

    try {
      final points = await _api.fetchHistoricalPrices(
        itemId: widget.item.id,
        timestep: _selectedTimestep,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _points = points;
        _timeseriesCacheAt = DateTime.now();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'No internet connection. Check your connection and retry.';
      });
    }
  }

  List<HistoricalPricePoint> get _validPoints => _points
      .where((point) => point.avgHighPrice != null && point.avgLowPrice != null)
      .toList();

  List<HistoricalPricePoint> get _displayPoints {
    final points = _validPoints;
    if (_chartMode == 'Bars' && points.length > 60) {
      return points.sublist(points.length - 60);
    }
    return points;
  }

  Map<String, double> _resolveYRange(List<HistoricalPricePoint> points) {
    final values = <double>[];

    for (final point in points) {
      if (_showHigh && point.avgHighPrice != null) {
        values.add(point.avgHighPrice!.toDouble());
      }
      if (_showLow && point.avgLowPrice != null) {
        values.add(point.avgLowPrice!.toDouble());
      }
    }

    if (values.isEmpty) {
      return <String, double>{'min': 0, 'max': 1};
    }

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final span = maxValue - minValue;
    final padding = span > 0
        ? span * 0.12
        : (maxValue == 0 ? 10.0 : maxValue * 0.12);

    return <String, double>{
      'min': minValue - padding,
      'max': maxValue + padding,
    };
  }

  double _percentageChange() {
    final validPoints = _validPoints;

    if (validPoints.length < 2) {
      return 0;
    }

    final first = validPoints.first.avgHighPrice!;
    final last = validPoints.last.avgHighPrice!;
    if (first == 0) {
      return 0;
    }

    return ((last - first) / first) * 100;
  }

  String _compactPrice(int value) {
    final formatter = NumberFormat.compact();
    return '${formatter.format(value)} gp';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('MMM d').format(date);
  }

  double _chartAxisInterval(double minY, double maxY) {
    return math.max(1, (maxY - minY) / 4);
  }

  String _formatChartAxisLabel(double value, double interval) {
    final magnitude = value.abs();
    if (magnitude < 1000) {
      final decimals = interval >= 1 ? 0 : 1;
      return value.toStringAsFixed(decimals);
    }

    final unit = magnitude >= 1000000000
        ? 1000000000.0
        : magnitude >= 1000000
        ? 1000000.0
        : 1000.0;
    final suffix = unit == 1000000000
        ? 'B'
        : unit == 1000000
        ? 'M'
        : 'K';
    final scaledInterval = interval / unit;
    final decimals = scaledInterval >= 1
        ? 0
        : (-math.log(scaledInterval) / math.ln10).ceil().clamp(0, 3);
    final label = (value / unit).toStringAsFixed(decimals);
    return '$label$suffix';
  }

  String _displayPrice(int? value) => PriceFormat.price(value);

  double _alchemyProfit() {
    return AlchemyProfit.calculate(
      item: widget.item,
      latestPrices: widget.latestPrices,
      natureRune: AlchemyProfit.findNatureRune(widget.allItems),
      currentHigh: widget.currentPrice?.high,
    );
  }

  void _toggleSeries(String series) {
    setState(() {
      if (series == 'High') {
        _showHigh = !_showHigh;
        if (!_showHigh && !_showLow) {
          _showHigh = true;
        }
      } else {
        _showLow = !_showLow;
        if (!_showHigh && !_showLow) {
          _showLow = true;
        }
      }
      _autoYScale = true;
      _manualMin = 0;
      _manualMax = 0;
      selectedX = null;
    });
  }

  void _openYScaleSheet() {
    final range = _resolveYRange(_displayPoints);
    var values = RangeValues(
      _autoYScale ? range['min']! : _manualMin,
      _autoYScale ? range['max']! : _manualMax,
    );

    if (values.start >= values.end) {
      values = RangeValues(range['min']!, range['max']!);
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          'Y-axis scale',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(modalContext);
                            setState(() {
                              _autoYScale = true;
                              _manualMin = 0;
                              _manualMax = 0;
                            });
                          },
                          icon: const Icon(
                            Icons.refresh,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RangeSlider(
                      min: range['min']!,
                      max: range['max']!,
                      values: values,
                      labels: RangeLabels(
                        '${values.start.round()} gp',
                        '${values.end.round()} gp',
                      ),
                      onChanged: (RangeValues newValues) {
                        setModalState(() {
                          values = newValues;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _autoYScale = true;
                              _manualMin = 0;
                              _manualMax = 0;
                            });
                            Navigator.pop(modalContext);
                          },
                          child: const Text('Auto'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentColor,
                          ),
                          onPressed: () {
                            Navigator.pop(modalContext);
                            setState(() {
                              _autoYScale = false;
                              _manualMin = values.start;
                              _manualMax = values.end;
                            });
                          },
                          child: const Text(
                            'Apply',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Formats a Duration as "2h 13m" or "13m 45s".
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Returns the color for the progress bar based on usage percentage.
  Color _getProgressColor(double percentage) {
    if (percentage >= 0.9) {
      return Colors.redAccent;
    } else if (percentage >= 0.7) {
      return Colors.amber;
    } else {
      return Colors.green;
    }
  }

  Widget _buildLimitProgress() {
    final entry = _currentLimitEntry;
    if (entry == null) return const SizedBox.shrink();

    final remainingTime = entry.remainingTime(LimitService.windowDuration);
    final percentage = entry.usedPercentage;
    final progressColor = _getProgressColor(percentage);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '${NumberFormat.decimalPattern('en_US').format(entry.quantityBought)} of ${NumberFormat.decimalPattern('en_US').format(entry.limit)} bought',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${NumberFormat.decimalPattern('en_US').format(entry.remaining)} remaining',
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFF3A3A3A),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          if (remainingTime != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppTheme.secondaryTextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'resets in ${_formatDuration(remainingTime)}',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openLimitTrackerSheet,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '+ Add',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openLimitTrackerSheet() async {
    final entry = _limitService.getActiveEntry(widget.item.id);
    final quantityController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return _LimitTrackerSheet(
              item: widget.item,
              entry: entry,
              quantityController: quantityController,
              onAdd: (int quantity) async {
                await _limitService.trackPurchase(
                  itemId: widget.item.id,
                  itemName: widget.item.name,
                  quantity: quantity,
                  currentLimit: widget.item.limit,
                );
                if (!mounted) return;
                _loadCurrentLimitEntry();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
              },
              onViewAllLimits: () {
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LimitsScreen(
                      allItems: widget.allItems,
                      latestPrices: widget.latestPrices,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
    quantityController.dispose();
  }

  Widget _buildVolumeChart() {
    final points = _displayPoints;
    if (points.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'No volume data',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    // Real traded units per window (high-side + low-side), not price spread.
    final volumes = <int?>[];
    for (final point in points) {
      final total = (point.highPriceVolume ?? 0) + (point.lowPriceVolume ?? 0);
      volumes.add(total > 0 ? total : null);
    }

    final maxVolume = volumes.whereType<int>().fold<int>(
      0,
      (int acc, int value) => value > acc ? value : acc,
    );

    if (maxVolume <= 0) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'No volume data',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    return SizedBox(
      height: 80,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVolume > 0 ? maxVolume * 1.2 : 1,
          barTouchData: BarTouchData(
            enabled: true,
            touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
              if (response == null) {
                if (selectedX != null) {
                  setState(() {
                    selectedX = null;
                  });
                }
                return;
              }

              final touchedSpot = response.spot;
              if (touchedSpot == null) {
                if (selectedX != null) {
                  setState(() {
                    selectedX = null;
                  });
                }
                return;
              }

              final touchedIndex = touchedSpot.touchedBarGroupIndex;
              if (touchedIndex < 0 || touchedIndex >= points.length) {
                if (selectedX != null) {
                  setState(() {
                    selectedX = null;
                  });
                }
                return;
              }

              if (selectedX != touchedIndex) {
                setState(() {
                  selectedX = touchedIndex;
                });
              }
            },
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(10),
              fitInsideHorizontally: true,
              tooltipMargin: 8,
              tooltipBorder: BorderSide.none,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[groupIndex];
                final volume = volumes[groupIndex];
                final label = volume == null
                    ? 'No trades'
                    : NumberFormat.compact().format(volume);
                return BarTooltipItem(
                  '$label\n${_formatDate(point.timestamp)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          barGroups: List.generate(volumes.length, (index) {
            final volume = volumes[index];
            if (volume == null) {
              return BarChartGroupData(
                x: index,
                barsSpace: 4,
                barRods: const <BarChartRodData>[],
              );
            }

            final isSelected = selectedX == index;
            return BarChartGroupData(
              x: index,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: volume.toDouble(),
                  width: 6,
                  color: isSelected
                      ? const Color(0xFF9AD8FF)
                      : const Color(0xFF9AA3B2),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                    bottom: Radius.zero,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBarChart(List<HistoricalPricePoint> points) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'No data for this period.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    final yRange = _resolveYRange(points);
    final minY = _autoYScale ? yRange['min']! : _manualMin;
    final maxY = _autoYScale ? yRange['max']! : _manualMax;

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          minY: minY,
          maxY: maxY,
          extraLinesData: ExtraLinesData(
            verticalLines: selectedX == null
                ? const <VerticalLine>[]
                : <VerticalLine>[
                    VerticalLine(
                      x: selectedX!.toDouble(),
                      color: const Color(0xFF7AD3FF).withValues(alpha: 0.65),
                      strokeWidth: 1.5,
                      dashArray: [6, 6],
                    ),
                  ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _chartAxisInterval(minY, maxY),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF2A2A2A), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: _chartAxisInterval(minY, maxY),
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatChartAxisLabel(
                      value,
                      _chartAxisInterval(minY, maxY),
                    ),
                    style: const TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (points.length - 1) / 3,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _formatDate(points[index].timestamp),
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barGroups: List.generate(points.length, (index) {
            final point = points[index];
            final high = point.avgHighPrice?.toDouble() ?? 0;
            final low = point.avgLowPrice?.toDouble() ?? 0;
            final isSelected = selectedX == index;

            return BarChartGroupData(
              x: index,
              barsSpace: 4,
              barRods: <BarChartRodData>[
                if (_showHigh)
                  BarChartRodData(
                    toY: high,
                    width: 5,
                    color: isSelected
                        ? const Color(0xFF9AD8FF)
                        : const Color(0xFF7AD3FF),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                      bottom: Radius.zero,
                    ),
                  ),
                if (_showLow)
                  BarChartRodData(
                    toY: low,
                    width: 5,
                    color: isSelected
                        ? const Color(0xFF9AF7C9)
                        : const Color(0xFF7CFFB2),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                      bottom: Radius.zero,
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLineChart(List<HistoricalPricePoint> points) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'No data for this period.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    final yRange = _resolveYRange(points);
    final minY = _autoYScale ? yRange['min']! : _manualMin;
    final maxY = _autoYScale ? yRange['max']! : _manualMax;

    final lineBarsData = <LineChartBarData>[];
    if (_showHigh) {
      lineBarsData.add(
        LineChartBarData(
          isCurved: true,
          color: const Color(0xFF7AD3FF),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF7AD3FF).withValues(alpha: 0.12),
          ),
          spots: List.generate(
            points.length,
            (index) => FlSpot(
              index.toDouble(),
              points[index].avgHighPrice!.toDouble(),
            ),
          ),
        ),
      );
    }
    if (_showLow) {
      lineBarsData.add(
        LineChartBarData(
          isCurved: true,
          color: const Color(0xFF7CFFB2),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF7CFFB2).withValues(alpha: 0.08),
          ),
          spots: List.generate(
            points.length,
            (index) =>
                FlSpot(index.toDouble(), points[index].avgLowPrice!.toDouble()),
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          extraLinesData: ExtraLinesData(
            verticalLines: selectedX == null
                ? const <VerticalLine>[]
                : <VerticalLine>[
                    VerticalLine(
                      x: selectedX!.toDouble(),
                      color: const Color(0xFF7AD3FF).withValues(alpha: 0.65),
                      strokeWidth: 1.5,
                      dashArray: [6, 6],
                    ),
                  ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _chartAxisInterval(minY, maxY),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF2A2A2A), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
              if (response == null ||
                  response.lineBarSpots == null ||
                  response.lineBarSpots!.isEmpty) {
                if (selectedX != null) {
                  setState(() {
                    selectedX = null;
                  });
                }
                return;
              }

              final spot = response.lineBarSpots!.first;
              final touchedIndex = spot.x.toInt();
              if (touchedIndex < 0 || touchedIndex >= points.length) {
                if (selectedX != null) {
                  setState(() {
                    selectedX = null;
                  });
                }
                return;
              }

              if (selectedX != touchedIndex) {
                setState(() {
                  selectedX = touchedIndex;
                });
              }
            },
            touchTooltipData: LineTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(10),
              fitInsideHorizontally: true,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final label = spot.barIndex == 0 ? 'High' : 'Low';
                  return LineTooltipItem(
                    '$label\n${_compactPrice(spot.y.toInt())}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: _chartAxisInterval(minY, maxY),
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatChartAxisLabel(
                      value,
                      _chartAxisInterval(minY, maxY),
                    ),
                    style: const TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (points.length - 1) / 3,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _formatDate(points[index].timestamp),
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: lineBarsData,
        ),
      ),
    );
  }

  Widget _buildChart() {
    final points = _displayPoints;
    if (points.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'No data for this period.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    final chart = _chartMode == 'Bars'
        ? _buildBarChart(points)
        : _buildLineChart(points);

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'Lines', label: Text('Lines')),
                ButtonSegment<String>(value: 'Bars', label: Text('Bars')),
              ],
              selected: <String>{_chartMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _chartMode = selection.first;
                  selectedX = null;
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color>((
                  states,
                ) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.accentColor;
                  }
                  return Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.resolveWith<Color>((
                  states,
                ) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.black;
                  }
                  return Colors.white;
                }),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _openYScaleSheet,
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'Adjust Y axis',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('High'),
              selected: _showHigh,
              onSelected: (_) => _toggleSeries('High'),
              selectedColor: const Color(0xFF7AD3FF),
              backgroundColor: AppTheme.panelColor,
              labelStyle: TextStyle(
                color: _showHigh ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            ChoiceChip(
              label: const Text('Low'),
              selected: _showLow,
              onSelected: (_) => _toggleSeries('Low'),
              selectedColor: const Color(0xFF7CFFB2),
              backgroundColor: AppTheme.panelColor,
              labelStyle: TextStyle(
                color: _showLow ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        chart,
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Volume (units)',
            style: TextStyle(
              color: AppTheme.secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildVolumeChart(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final percentageChange = _percentageChange();
    final changeColor = percentageChange >= 0 ? Colors.green : Colors.red;
    final currentHigh = widget.currentPrice?.high;
    final currentLow = widget.currentPrice?.low;
    final grossMargin =
        currentHigh != null &&
            currentLow != null &&
            currentHigh > 0 &&
            currentLow > 0
        ? currentHigh - currentLow
        : null;
    final netMargin =
        currentHigh != null &&
            currentLow != null &&
            currentHigh > 0 &&
            currentLow > 0
        ? GeTax.netMargin(high: currentHigh, low: currentLow)
        : null;
    final netMarginPct =
        currentLow != null && currentLow > 0 && netMargin != null
        ? (netMargin / currentLow) * 100
        : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (PriceAlertsBackgroundService.isAndroid)
            IconButton(
              onPressed: _openPriceAlertSheet,
              tooltip: 'Price alerts',
              icon: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  const Icon(Icons.notifications_none),
                  if (_activeItemAlerts.isNotEmpty)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          IconButton(
            onPressed: _openWiki,
            icon: const Icon(Icons.open_in_new),
            tooltip: 'View on wiki',
          ),
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? Colors.amber : Colors.white,
            ),
          ),
          IconButton(
            onPressed: _shareChart,
            icon: const Icon(Icons.share),
            tooltip: 'Share chart',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: widget.item.icon.trim().isEmpty
                          ? const Icon(
                              Icons.inventory_2,
                              color: AppTheme.secondaryTextColor,
                            )
                          : CachedNetworkImage(
                              imageUrl:
                                  'https://oldschool.runescape.wiki/images/${widget.item.icon.replaceAll(' ', '_')}',
                              memCacheWidth: 64,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => Container(
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(
                                  Icons.inventory_2,
                                  color: AppTheme.secondaryTextColor,
                                ),
                              ),
                              errorWidget: (context, url, error) => const Icon(
                                Icons.inventory_2,
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.item.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.item.limit > 0) ...<Widget>[
                            const SizedBox(height: 4),
                            Row(
                              children: <Widget>[
                                Text(
                                  'Buy limit: ${NumberFormat.decimalPattern('en_US').format(widget.item.limit)}',
                                  style: const TextStyle(
                                    color: AppTheme.secondaryTextColor,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _openLimitTrackerSheet,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Track my buys',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_currentLimitEntry != null) ...<Widget>[
                              const SizedBox(height: 8),
                              _buildLimitProgress(),
                            ],
                          ],
                          if (widget.item.examine
                              .trim()
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              widget.item.examine,
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'High: ${_displayPrice(currentHigh)}',
                            style: const TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                          Text(
                            'Low: ${_displayPrice(currentLow)}',
                            style: const TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.item.highAlch > 0) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.panelColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Alchemy',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'High alch: ${PriceFormat.price(widget.item.highAlch)}',
                          style: const TextStyle(
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Alch profit (est.): ${PriceFormat.price(_alchemyProfit().round())}',
                          style: TextStyle(
                            color: _alchemyProfit() > 0
                                ? Colors.green
                                : Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'assumes fire staff equipped, only nature rune cost',
                          style: TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.panelColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            'Period change',
                            style: TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                          Text(
                            '${percentageChange >= 0 ? '+' : ''}${percentageChange.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: changeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (grossMargin != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Gross margin: ${PriceFormat.price(grossMargin)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                      if (netMargin != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'Net est.: ${PriceFormat.price(netMargin.round())} ${netMarginPct >= 0 ? '(+${netMarginPct.toStringAsFixed(1)}%)' : '(${netMarginPct.toStringAsFixed(1)}%)'}',
                          style: TextStyle(
                            color: netMargin >= 0
                                ? Colors.green
                                : Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: _openWiki,
                  icon: const Icon(Icons.public),
                  label: const Text('View on wiki'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: _timestepOptions
                            .map(
                              (value) => ButtonSegment<String>(
                                value: value,
                                label: Text(value),
                              ),
                            )
                            .toList(),
                        selected: <String>{_selectedTimestep},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _selectedTimestep = selection.first;
                            _autoYScale = true;
                            _manualMin = 0;
                            _manualMax = 0;
                            selectedX = null;
                          });
                          _loadData();
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return AppTheme.accentColor;
                                }
                                return Colors.transparent;
                              }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.black;
                                }
                                return Colors.white;
                              }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UpdatedBadge(lastUpdated: _timeseriesCacheAt),
                  ],
                ),
                const SizedBox(height: 18),
                if (_isLoading)
                  const ChartBlockSkeleton(height: 260)
                else if (_errorMessage != null)
                  SizedBox(
                    height: 260,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _loadData(forceRefresh: true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  RepaintBoundary(
                    key: _chartBoundaryKey,
                    child: _buildChart(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet widget for tracking buy limit purchases.
class _LimitTrackerSheet extends StatefulWidget {
  const _LimitTrackerSheet({
    required this.item,
    required this.entry,
    required this.quantityController,
    required this.onAdd,
    required this.onViewAllLimits,
  });

  final ItemMapping item;
  final LimitEntry? entry;
  final TextEditingController quantityController;
  final void Function(int quantity) onAdd;
  final VoidCallback onViewAllLimits;

  @override
  State<_LimitTrackerSheet> createState() => _LimitTrackerSheetState();
}

class _LimitTrackerSheetState extends State<_LimitTrackerSheet> {
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 0.9) {
      return Colors.redAccent;
    } else if (percentage >= 0.7) {
      return Colors.amber;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final remainingTime = entry?.remainingTime(LimitService.windowDuration);
    final percentage = entry?.usedPercentage ?? 0.0;
    final progressColor = _getProgressColor(percentage);
    final quantity = int.tryParse(widget.quantityController.text) ?? 0;
    final isValidQuantity = quantity > 0;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onViewAllLimits,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                    ),
                    child: const Text('My limits'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (entry != null && remainingTime != null) ...<Widget>[
                Text(
                  '${NumberFormat.decimalPattern('en_US').format(entry.quantityBought)} of ${NumberFormat.decimalPattern('en_US').format(entry.limit)} bought',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${NumberFormat.decimalPattern('en_US').format(entry.remaining)} remaining',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: const Color(0xFF3A3A3A),
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: AppTheme.secondaryTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'resets in ${_formatDuration(remainingTime)}',
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ] else ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.panelColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.info_outline,
                        color: AppTheme.accentColor,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No active window. Add your first purchase to start tracking.',
                          style: TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: widget.quantityController,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Quantity bought',
                  hintText: 'Enter amount',
                  suffixText: 'max: ${NumberFormat.decimalPattern('en_US').format(entry?.remaining ?? widget.item.limit)}',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isValidQuantity
                      ? () => widget.onAdd(quantity)
                      : null,
                  child: Text(entry != null ? 'Add to window' : 'Start tracking'),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Window resets every 4 hours',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
