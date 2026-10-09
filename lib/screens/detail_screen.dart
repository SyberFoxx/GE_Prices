import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/item_price.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../utils/alchemy_profit.dart';
import '../utils/ge_tax.dart';
import '../utils/price_format.dart';
import '../widgets/skeletons.dart';
import '../widgets/updated_badge.dart';

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
  static const String _favoriteKey = 'favorite_item_ids';
  static const Duration _timeseriesCacheTtl = Duration(minutes: 5);

  late SharedPreferences _prefs;
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
    _initFavoriteState();
    _loadData();
  }

  Future<void> _initFavoriteState() async {
    _prefs = await SharedPreferences.getInstance();
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

  Future<void> _loadData() async {
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
        _errorMessage = 'No internet connection. Check your connection and retry.';
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

    final volumes = <double?>[];
    for (final point in points) {
      final high = point.avgHighPrice ?? 0;
      final low = point.avgLowPrice ?? 0;
      final spread = (high - low).abs();
      volumes.add(spread > 0 ? spread.toDouble() : null);
    }

    final maxVolume = volumes.whereType<double>().fold<double>(
      0,
      (double acc, double value) => value > acc ? value : acc,
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
                    : NumberFormat.compact().format(volume.round());
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
                  toY: volume,
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
            'Volume',
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
                            Text(
                              'Buy limit: ${NumberFormat.decimalPattern('en_US').format(widget.item.limit)}',
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
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
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _buildChart(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
