import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, this.currentPrice});

  final ItemMapping item;
  final ItemPrice? currentPrice;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final OsrsApi _api = OsrsApi();
  static const String _favoriteKey = 'favorite_item_ids';

  late SharedPreferences _prefs;
  List<HistoricalPricePoint> _points = <HistoricalPricePoint>[];
  bool _isLoading = true;
  bool _isFavorite = false;
  String? _errorMessage;
  String _selectedTimestep = '24h';

  static const List<String> _timestepOptions = <String>[
    '5m',
    '1h',
    '6h',
    '24h',
  ];

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudo cargar la gráfica histórica. Inténtalo de nuevo.';
      });
    }
  }

  String _formatNumber(int value) {
    final formatter = NumberFormat.decimalPattern('en_US');
    return formatter.format(value);
  }

  String _compactPrice(int value) {
    final formatter = NumberFormat.compact();
    return '${formatter.format(value)} gp';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('MMM d').format(date);
  }

  String _displayPrice(int? value) {
    if (value == null) {
      return '—';
    }

    return '${_formatNumber(value)} gp';
  }

  double _percentageChange() {
    final validPoints = _points
        .where(
          (point) => point.avgHighPrice != null && point.avgLowPrice != null,
        )
        .toList();

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

  Widget _buildChart() {
    final validPoints = _points
        .where(
          (point) => point.avgHighPrice != null && point.avgLowPrice != null,
        )
        .toList();

    if (validPoints.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'No hay datos para este período.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
        ),
      );
    }

    final maxValue = validPoints
        .reduce(
          (current, next) =>
              current.avgHighPrice! > next.avgHighPrice! ? current : next,
        )
        .avgHighPrice!;
    final minValue = validPoints
        .reduce(
          (current, next) =>
              current.avgLowPrice! < next.avgLowPrice! ? current : next,
        )
        .avgLowPrice!;
    final yMin = (minValue * 0.9).floorToDouble();
    final yMax = (maxValue * 1.1).ceilToDouble();

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minY: yMin,
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (yMax - yMin) / 4,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF2A2A2A), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
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
                interval: (yMax - yMin) / 3,
                getTitlesWidget: (value, meta) {
                  return Text(
                    NumberFormat.compact().format(value.toInt()),
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
                interval: (validPoints.length - 1) / 3,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= validPoints.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _formatDate(validPoints[index].timestamp),
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
          lineBarsData: [
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
                validPoints.length,
                (index) => FlSpot(
                  index.toDouble(),
                  validPoints[index].avgHighPrice!.toDouble(),
                ),
              ),
            ),
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
                validPoints.length,
                (index) => FlSpot(
                  index.toDouble(),
                  validPoints[index].avgLowPrice!.toDouble(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final percentageChange = _percentageChange();
    final changeColor = percentageChange >= 0 ? Colors.green : Colors.red;
    final currentHigh = widget.currentPrice?.high;
    final currentLow = widget.currentPrice?.low;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: <Widget>[
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.panelColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'Cambio del período',
                      style: TextStyle(color: AppTheme.secondaryTextColor),
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
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
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
                  });
                  _loadData();
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
              const SizedBox(height: 18),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accentColor,
                    ),
                  ),
                )
              else if (_errorMessage != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              else
                Expanded(child: _buildChart()),
            ],
          ),
        ),
      ),
    );
  }
}
