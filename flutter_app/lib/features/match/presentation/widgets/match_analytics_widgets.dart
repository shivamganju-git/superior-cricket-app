import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/cricket_engine/models/delivery_model.dart';
import 'dart:math' as math;

/// Analytics widgets for match details
/// Includes: Manhattan, Wagon Wheel, Worm, Run Rate, Partnership, Types of Runs, Wickets

class MatchAnalyticsWidgets {
  /// Build Manhattan graph (runs per over)
  static Widget buildManhattanChart({
    required List<DeliveryModel> team1Deliveries,
    required List<DeliveryModel> team2Deliveries,
    required String team1Name,
    required String team2Name,
    required int maxOvers,
  }) {
    // Group deliveries by over for both teams
    final team1OverData = _groupDeliveriesByOver(team1Deliveries, maxOvers);
    final team2OverData = _groupDeliveriesByOver(team2Deliveries, maxOvers);

    // Dynamic Max Y Calculation
    int maxRunsInOver = 0;
    for (var runs in team1OverData) {
      if (runs > maxRunsInOver) maxRunsInOver = runs;
    }
    for (var runs in team2OverData) {
      if (runs > maxRunsInOver) maxRunsInOver = runs;
    }
    
    // Round up to nearest 5 or at least 10, plus some buffer
    final double maxY = (math.max(maxRunsInOver, 10).toDouble() / 5).ceil() * 5.0 + 5.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: 340, // Slightly increased height for better spacing
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manhattan',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                // Kept generic options but made them smaller/subtle
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 20, color: Colors.grey[400]),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Legend
            Row(
              children: [
                _buildLegendItem(team1Name, const Color(0xFF2196F3)), // Material Blue
                const SizedBox(width: 24),
                _buildLegendItem(team2Name, const Color(0xFFFF9800)), // Material Orange
              ],
            ),
            const SizedBox(height: 24), // More breathing room
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: 0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tooltipBgColor: const Color(0xFF263238), // Dark Blue Grey
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final over = group.x.toInt() + 1; // 1-based over for display
                        final runs = rod.toY.toInt();
                        final isTeam1 = rod.color == const Color(0xFF2196F3);
                        
                        // Find wickets in this specific over
                        final deliveries = isTeam1 ? team1Deliveries : team2Deliveries;
                        final wickets = _getWicketsInOver(deliveries, group.x.toInt());

                        final teamName = isTeam1 ? team1Name : team2Name;

                        return BarTooltipItem(
                          '$teamName\n',
                          const TextStyle(
                            color: Colors.white70, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 10
                          ),
                          children: [
                            TextSpan(
                              text: 'Over $over: ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            TextSpan(
                              text: '$runs Runs',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (wickets > 0)
                              TextSpan(
                                text: '\n$wickets Wicket${wickets > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final overIndex = value.toInt();
                          // Show label every 2 overs if maxOvers <= 20, else every 5
                          final interval = maxOvers <= 24 ? 2 : 5;
                          
                          if ((overIndex + 1) % interval == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                (overIndex + 1).toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[600],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          
                          // Dynamic interval calculation
                          // If maxY is 25, interval 5. If 40, interval 10.
                          int interval = 5;
                          if (maxY > 30) interval = 10;
                          
                          if (value.toInt() % interval == 0) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.right,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 30, // Conserved space
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true, 
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.1),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                      left: BorderSide(color: Colors.grey[300]!, width: 1),
                    ),
                  ),
                  barGroups: List.generate(maxOvers, (index) {
                    final team1Runs = index < team1OverData.length ? team1OverData[index] : 0;
                    final team2Runs = index < team2OverData.length ? team2OverData[index] : 0;
                    
                    return BarChartGroupData(
                      x: index,
                      barsSpace: 4, // Spacing between bars of same group
                      barRods: [
                        BarChartRodData(
                          toY: team1Runs.toDouble(),
                          color: const Color(0xFF2196F3),
                          width: 8, // Thicker bars
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: Colors.grey.withOpacity(0.05),
                          ),
                        ),
                        BarChartRodData(
                          toY: team2Runs.toDouble(),
                          color: const Color(0xFFFF9800),
                          width: 8,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: Colors.grey.withOpacity(0.05),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Wagon Wheel (shot placement)
  static Widget buildWagonWheel({
    required List<DeliveryModel> deliveries,
    required String teamName,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: 420,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Wagon Wheel',
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.2, end: 0, curve: Curves.easeOut),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Shows the distribution of runs across the field',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Icon(Icons.info_outline, size: 16, color: Colors.grey[400])
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
                    ),
                  ],
                ),
                Icon(Icons.pie_chart_outline_rounded, size: 20, color: Colors.grey[400])
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .rotate(begin: -0.1, end: 0, duration: 500.ms, delay: 100.ms),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              teamName,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
            )
              .animate()
              .fadeIn(duration: 400.ms, delay: 150.ms)
              .slideX(begin: -0.1, end: 0),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0, // Square aspect ratio for the circular field
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Layer 1: Professional Cricket Ground Image
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/cricket_ground.png',
                          fit: BoxFit.cover,
                        ),
                      )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 200.ms)
                        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 600.ms, delay: 200.ms),
                      // Layer 2: Shot Analysis Overlay - Animated
                      _AnimatedWagonWheel(deliveries: deliveries),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildWagonWheelLegendItem('Out', Colors.orange, 0),
                _buildWagonWheelLegendItem("0's", Colors.grey[300]!, 1),
                _buildWagonWheelLegendItem("1's", Colors.lightBlue, 2),
                _buildWagonWheelLegendItem("2's & 3's", Colors.yellow[700]!, 3),
                _buildWagonWheelLegendItem("4's", Colors.purple, 4),
                _buildWagonWheelLegendItem("6's", Colors.red, 5),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build Worm graph (cumulative runs)
  static Widget buildWormChart({
    required List<DeliveryModel> team1Deliveries,
    required List<DeliveryModel> team2Deliveries,
    required String team1Name,
    required String team2Name,
    required int maxOvers,
  }) {
    final team1Data = _getCumulativeRuns(team1Deliveries, maxOvers);
    final team2Data = _getCumulativeRuns(team2Deliveries, maxOvers);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: 340,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Worm',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(Icons.show_chart_rounded, size: 20, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildLegendItem(team1Name, const Color(0xFF2196F3)),
                const SizedBox(width: 24),
                _buildLegendItem(team2Name, const Color(0xFFFF9800)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipRoundedRadius: 8,
                      tooltipBgColor: const Color(0xFF263238),
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final totalBalls = (spot.x * 6).round();
                          final over = (totalBalls / 6).floor();
                          final ball = totalBalls % 6;
                          final overStr = ball == 0 ? '$over' : '$over.$ball';
                          
                          final runs = spot.y.toInt();
                          final isTeam1 = spot.barIndex == 0;
                          return LineTooltipItem(
                            '${isTeam1 ? team1Name : team2Name}\n',
                            const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10),
                            children: [
                              TextSpan(
                                text: 'Over $overStr: ',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.normal),
                              ),
                              TextSpan(
                                text: '$runs Runs',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.1),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() % 20 == 0) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                      left: BorderSide(color: Colors.grey[300]!, width: 1),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: team1Data,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFF2196F3),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) => (spot.x * 6).round() % 6 == 0,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFF2196F3),
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF2196F3).withOpacity(0.05),
                      ),
                    ),
                    LineChartBarData(
                      spots: team2Data,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFFFF9800),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) => (spot.x * 6).round() % 6 == 0,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFFFF9800),
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFFFF9800).withOpacity(0.05),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Run Rate graph
  static Widget buildRunRateChart({
    required List<DeliveryModel> team1Deliveries,
    required List<DeliveryModel> team2Deliveries,
    required String team1Name,
    required String team2Name,
    required int maxOvers,
  }) {
    final team1Data = _getRunRateData(team1Deliveries, maxOvers);
    final team2Data = _getRunRateData(team2Deliveries, maxOvers);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: 340,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Run Rate',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(Icons.trending_up_rounded, size: 20, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildLegendItem(team1Name, const Color(0xFF2196F3)),
                const SizedBox(width: 24),
                _buildLegendItem(team2Name, const Color(0xFFFF9800)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipRoundedRadius: 8,
                      tooltipBgColor: const Color(0xFF263238),
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final overNum = spot.x.toInt();
                          final rr = spot.y.toStringAsFixed(2);
                          final isTeam1 = spot.barIndex == 0;
                          return LineTooltipItem(
                            '${isTeam1 ? team1Name : team2Name}\n',
                            const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10),
                            children: [
                              TextSpan(
                                text: 'Over $overNum: ',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.normal),
                              ),
                              TextSpan(
                                text: '$rr RR',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.1),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() % 2 == 0) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                      left: BorderSide(color: Colors.grey[300]!, width: 1),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: team1Data,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFF2196F3),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFF2196F3),
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF2196F3).withOpacity(0.05),
                      ),
                    ),
                    LineChartBarData(
                      spots: team2Data,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFFFF9800),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFFFF9800),
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFFFF9800).withOpacity(0.05),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Partnership chart
  static Widget buildPartnershipChart({
    required List<DeliveryModel> deliveries,
    required String teamName,
  }) {
    final partnerships = _calculatePartnerships(deliveries);
    
    // Calculate dynamic height based on number of partnerships
    // Each partnership container is ~140px (padding + content + margin) - increased size
    final baseHeight = 100.0; // Header + team name + spacing
    final itemHeight = 140.0; // Height per partnership container (increased from 100)
    final minHeight = 200.0;
    final maxHeight = 600.0; // Increased max height before scrolling kicks in
    final calculatedHeight = baseHeight + (partnerships.length * itemHeight);
    // Container grows up to maxHeight, then enables scrolling
    final containerHeight = calculatedHeight.clamp(minHeight, maxHeight);
    final needsScrolling = calculatedHeight > maxHeight;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: containerHeight,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Partnerships',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.2, end: 0, curve: Curves.easeOut),
                Icon(Icons.people_outline_rounded, size: 20, color: Colors.grey[400])
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              teamName,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: partnerships.isEmpty
                  ? Center(
                      child: Text(
                        'No partnerships data available',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: false,
                      physics: needsScrolling 
                          ? const AlwaysScrollableScrollPhysics() 
                          : const ClampingScrollPhysics(),
                      itemCount: partnerships.length,
                      itemBuilder: (context, index) {
                        final p = partnerships[index];
                        return _buildPartnershipBar(p, index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Types of Runs chart (Butterfly Comparison Chart)
  static Widget buildTypesOfRunsChart({
    required List<DeliveryModel> team1Deliveries,
    required List<DeliveryModel> team2Deliveries,
    required String team1Name,
    required String team2Name,
  }) {
    final team1Runs = _getTypesOfRuns(team1Deliveries);
    final team2Runs = _getTypesOfRuns(team2Deliveries);

    // Dynamic Max Calculation for scaling
    int maxCount = 0;
    for (var count in team1Runs.values) {
      if (count > maxCount) maxCount = count;
    }
    for (var count in team2Runs.values) {
      if (count > maxCount) maxCount = count;
    }
    final int chartMax = math.max(maxCount, 1) + 5; // Buffer for labels

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Types of Runs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E1E1E),
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(Icons.compare_arrows_rounded, size: 20, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Team Wise Distribution',
              style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    team1Name.toUpperCase(),
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2196F3),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 80), // Space for labels
                Expanded(
                  child: Text(
                    team2Name.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF9800),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Butterfly Rows
            ...[1, 2, 3, 4, 6].map((runType) {
              final t1Count = team1Runs[runType] ?? 0;
              final t2Count = team2Runs[runType] ?? 0;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    // Team 1 Bar (Left)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (t1Count > 0)
                            Text(
                              '$t1Count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FractionallySizedBox(
                                widthFactor: math.min(t1Count / chartMax, 1.0),
                                child: Container(
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF64B5F6), Color(0xFF2196F3)],
                                    ),
                                    borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Run Label (Center)
                    Container(
                      width: 60,
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          '${runType}s',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                    // Team 2 Bar (Right)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: math.min(t2Count / chartMax, 1.0),
                                child: Container(
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                                    ),
                                    borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (t2Count > 0)
                            Text(
                              '$t2Count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[800],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// Build Wickets pie chart
  static Widget buildWicketsChart({
    required List<DeliveryModel> team1Deliveries,
    required List<DeliveryModel> team2Deliveries,
  }) {
    final allDeliveries = [...team1Deliveries, ...team2Deliveries];
    final wicketTypes = _getWicketTypes(allDeliveries);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        height: 400,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Wickets',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.2, end: 0, curve: Curves.easeOut),
                Icon(Icons.pie_chart_outline_rounded, size: 20, color: Colors.grey[400])
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1))
                  .rotate(begin: -0.1, end: 0, duration: 500.ms, delay: 100.ms),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 60,
                  sections: wicketTypes.entries.map((entry) {
                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      title: '${entry.value.toStringAsFixed(0)}',
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      color: _getWicketTypeColor(entry.key),
                      radius: 80,
                    );
                  }).toList(),
                ),
              )
                .animate()
                .fadeIn(duration: 600.ms, delay: 200.ms)
                .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 800.ms, delay: 200.ms, curve: Curves.elasticOut)
                .rotate(begin: -0.3, end: 0, duration: 800.ms, delay: 200.ms, curve: Curves.easeOutCubic),
            ),
            const SizedBox(height: 24),
            // Legend
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: wicketTypes.entries.toList().asMap().entries.map((mapEntry) {
                final index = mapEntry.key;
                final entry = mapEntry.value;
                return _buildWicketLegendItem(entry.key, _getWicketTypeColor(entry.key), index);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  static List<int> _groupDeliveriesByOver(List<DeliveryModel> deliveries, int maxOvers) {
    final overData = List<int>.filled(maxOvers, 0);
    for (final d in deliveries) {
      if (d.over < maxOvers && d.isLegalBall) {
        overData[d.over] += d.totalRuns;
      }
    }
    return overData;
  }

  static int _getWicketsInOver(List<DeliveryModel> deliveries, int over) {
    return deliveries.where((d) => d.over == over && d.wicketType != null).length;
  }

  static List<FlSpot> _getCumulativeRuns(List<DeliveryModel> deliveries, int maxOvers) {
    final spots = <FlSpot>[];
    spots.add(const FlSpot(0, 0)); // Start at the origin (0,0)
    
    int cumulativeRuns = 0;
    int legalBalls = 0;
    
    for (final d in deliveries) {
      cumulativeRuns += d.totalRuns;
      if (d.isLegalBall) {
        legalBalls++;
      }
      
      // Calculate true over progress (e.g., 1 ball is 0.166, 6 balls is 1.0)
      final currentOverProgress = legalBalls / 6.0;
      if (currentOverProgress > maxOvers) break;
      
      // If we have multiple entries at the same over progress (e.g., due to extras),
      // we update the runs for that specific point to show the latest total.
      if (spots.isNotEmpty && (spots.last.x - currentOverProgress).abs() < 0.0001) {
        spots[spots.length - 1] = FlSpot(currentOverProgress, cumulativeRuns.toDouble());
      } else {
        spots.add(FlSpot(currentOverProgress, cumulativeRuns.toDouble()));
      }
    }
    
    return spots;
  }

  static List<FlSpot> _getRunRateData(List<DeliveryModel> deliveries, int maxOvers) {
    final spots = <FlSpot>[];
    final overData = _groupDeliveriesByOver(deliveries, maxOvers);
    
    for (int i = 0; i < overData.length; i++) {
      final runRate = overData[i].toDouble(); // Runs per over
      spots.add(FlSpot(i.toDouble(), runRate));
    }
    
    return spots;
  }

  static Map<int, int> _getTypesOfRuns(List<DeliveryModel> deliveries) {
    final runs = <int, int>{};
    for (final d in deliveries) {
      if (d.isLegalBall && d.runs > 0) {
        final runType = d.runs.clamp(1, 6);
        runs[runType] = (runs[runType] ?? 0) + 1;
      }
    }
    return runs;
  }

  static Map<String, int> _getWicketTypes(List<DeliveryModel> deliveries) {
    final types = <String, int>{};
    for (final d in deliveries) {
      if (d.wicketType != null) {
        final type = _normalizeWicketType(d.wicketType!);
        types[type] = (types[type] ?? 0) + 1;
      }
    }
    return types;
  }

  static String _normalizeWicketType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('caught') || lower.contains('catch')) {
      return 'Caught';
    } else if (lower.contains('bowled')) {
      return 'Bowled';
    } else if (lower.contains('lbw')) {
      return 'LBW';
    } else if (lower.contains('run out') || lower.contains('runout')) {
      return 'Run out';
    } else if (lower.contains('stumped')) {
      return 'Stumped';
    } else if (lower.contains('hit wicket') || lower.contains('hitwicket')) {
      return 'Hit Wicket';
    }
    return type;
  }

  static Color _getWicketTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'caught':
        return const Color(0xFF2196F3); // Blue
      case 'bowled':
        return const Color(0xFFFF9800); // Orange
      case 'lbw':
        return const Color(0xFF4CAF50); // Green
      case 'run out':
        return const Color(0xFF9C27B0); // Purple
      case 'stumped':
        return const Color(0xFF00BCD4); // Cyan
      case 'hit wicket':
        return const Color(0xFFE91E63); // Pink
      default:
        return Colors.grey;
    }
  }

  static List<Map<String, dynamic>> _calculatePartnerships(List<DeliveryModel> deliveries) {
    // Simplified partnership calculation
    // In real implementation, track batsmen pairs
    final partnerships = <Map<String, dynamic>>[];
    String? currentBatsman1;
    String? currentBatsman2;
    int partnershipRuns = 0;
    int partnershipBalls = 0;
    
    for (final d in deliveries) {
      if (d.isLegalBall) {
        if (currentBatsman1 == null) {
          currentBatsman1 = d.striker;
          currentBatsman2 = d.nonStriker;
        }
        
        if (d.striker == currentBatsman1 || d.striker == currentBatsman2) {
          partnershipRuns += d.runs;
          partnershipBalls++;
        } else {
          // New partnership
          if (currentBatsman1 != null && currentBatsman2 != null) {
            partnerships.add({
              'player1': currentBatsman1,
              'player2': currentBatsman2,
              'runs': partnershipRuns,
              'balls': partnershipBalls,
            });
          }
          currentBatsman1 = d.striker;
          currentBatsman2 = d.nonStriker;
          partnershipRuns = d.runs;
          partnershipBalls = 1;
        }
        
        if (d.wicketType != null) {
          // Partnership ended
          if (currentBatsman1 != null && currentBatsman2 != null) {
            partnerships.add({
              'player1': currentBatsman1,
              'player2': currentBatsman2,
              'runs': partnershipRuns,
              'balls': partnershipBalls,
            });
          }
          currentBatsman1 = null;
          currentBatsman2 = null;
          partnershipRuns = 0;
          partnershipBalls = 0;
        }
      }
    }
    
    return partnerships;
  }

  static Widget _buildPartnershipBar(Map<String, dynamic> partnership, int index) {
    final player1 = partnership['player1'] as String? ?? 'Unknown';
    final player2 = partnership['player2'] as String? ?? 'Unknown';
    final runs = partnership['runs'] as int? ?? 0;
    final balls = partnership['balls'] as int? ?? 0;
    
    // Calculate max runs for scaling (use 100 as base, or actual max if higher)
    final maxRuns = math.max(100, runs);
    final widthFactor = runs / maxRuns;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  player1,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
                ),
                child: Text(
                  '$runs($balls)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  player2,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              FractionallySizedBox(
                widthFactor: widthFactor.clamp(0.0, 1.0),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue[400]!, Colors.blue[600]!],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                )
                  .animate()
                  .scaleX(begin: 0, end: 1, duration: 600.ms, delay: (index * 100).ms, curve: Curves.easeOutCubic),
              ),
            ],
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 400.ms, delay: (index * 80).ms)
      .slideY(begin: 0.2, end: 0, duration: 400.ms, delay: (index * 80).ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 400.ms, delay: (index * 80).ms);
  }

  static Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.rectangle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  static Widget _buildWagonWheelLegendItem(String label, Color color, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.rectangle,
          ),
        )
          .animate()
          .scale(begin: const Offset(0, 0), end: const Offset(1, 1), duration: 300.ms, delay: (index * 80 + 600).ms, curve: Curves.elasticOut),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        )
          .animate()
          .fadeIn(duration: 300.ms, delay: (index * 80 + 650).ms)
          .slideX(begin: -0.2, end: 0, duration: 300.ms, delay: (index * 80 + 650).ms),
      ],
    )
      .animate()
      .fadeIn(duration: 400.ms, delay: (index * 80 + 600).ms)
      .slideY(begin: 0.2, end: 0, duration: 400.ms, delay: (index * 80 + 600).ms, curve: Curves.easeOutCubic);
  }

  static Widget _buildWicketLegendItem(String label, Color color, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        )
          .animate()
          .scale(begin: const Offset(0, 0), end: const Offset(1, 1), duration: 300.ms, delay: (index * 100 + 400).ms, curve: Curves.elasticOut),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        )
          .animate()
          .fadeIn(duration: 300.ms, delay: (index * 100 + 450).ms)
          .slideX(begin: -0.2, end: 0, duration: 300.ms, delay: (index * 100 + 450).ms),
      ],
    )
      .animate()
      .fadeIn(duration: 400.ms, delay: (index * 100 + 400).ms)
      .slideY(begin: 0.2, end: 0, duration: 400.ms, delay: (index * 100 + 400).ms, curve: Curves.easeOutCubic);
  }
}

/// Custom painter for Wagon Wheel
class WagonWheelPainter extends CustomPainter {
  final List<DeliveryModel> deliveries;

  WagonWheelPainter(this.deliveries);

  @override
  void paint(Canvas canvas, Size size) {
    // The image backdrop handles the field, pitch, and boundary visuals.
    // We only need to draw the shots originating from the center of the pitch.
    
    final center = Offset(size.width / 2, size.height / 2);
    // Radius is half the width (square aspect ratio assumed)
    // We leave a small margin so shots don't clip at the very edge
    final radius = (size.width / 2) * 0.9; 

    // Origin for shots is the center of the pitch
    final shotOrigin = center;

    for (final d in deliveries) {
      if (d.isLegalBall && d.runs > 0) {
        final angle = _getShotAngle(d); // Function enhanced for 360 distribution
        final distance = _getShotDistance(d.runs);
        
        // Calculate end point
        // Note: In Flutter, 0 is Right, PI/2 is Down. 
        // We want accurate cricket angles relative to the pitch.
        final endX = center.dx + math.cos(angle) * distance * radius;
        final endY = center.dy + math.sin(angle) * distance * radius;
        
        final isOut = d.wicketType != null;
        final color = _getShotColor(d.runs, isOut);

        final shotPaint = Paint()
          ..color = color.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isOut ? 3.0 : 2.0
          ..strokeCap = StrokeCap.round;
        
        canvas.drawLine(shotOrigin, Offset(endX, endY), shotPaint);
        
        // Draw a small dot/marker at the end where the ball stopped/crossed
        final markerPaint = Paint()..color = color;
        canvas.drawCircle(Offset(endX, endY), isOut ? 4.0 : 2.5, markerPaint);
        
        // Optional: Add a subtle glow for boundaries
        if (d.runs >= 4) {
          final glowPaint = Paint()
            ..color = color.withOpacity(0.3)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
           canvas.drawLine(shotOrigin, Offset(endX, endY), glowPaint);
        }
      }
    }
  }

  double _getShotAngle(DeliveryModel d) {
    // Determine shot direction based on randomness seeded by delivery content
    // This simulates realistic shot placement 360 degrees around the wicket
    
    // Create a seed based on unique delivery properties to keep it deterministic
    // (We want the chart to look the same every time for the same play)
    final seed = d.over * 100 + d.ball + d.runs + (d.striker.length);
    final random = math.Random(seed);
    
    // Base regions based on runs (simulating typical cricket shots)
    // 0 = 3 o'clock (Cover/Point)
    // PI/2 = 6 o'clock (Straight down ground / Long on/off - wait, usually wagon wheels are top-down?)
    // Let's assume standard unit circle: 0 is Right, -PI/2 is Up, PI is Left, PI/2 is Down.
    // In our top-down view:
    // Top (Up) = Straight Drive / Behind Wicket? 
    // Usually Top is "Straight down the ground" relative to camera, or "Behind" relative to keeper?
    // Let's assume "Top" is Straight Drive/Bowler's End for standard TV view. 
    // And "Bottom" is Wicket Keeper/Fine Leg.
    // So -PI/2 is Straight Drive. PI/2 is Keeper.
    
    // Run-based heuristics for realism:
    double baseAngle;
    
    if (d.runs == 6) {
      // 6s usually straight, cow corner, or square leg
      final zone = random.nextInt(3); 
      if (zone == 0) baseAngle = -math.pi / 2; // Straight (Up)
      else if (zone == 1) baseAngle = -math.pi / 4; // Long On (Up-Right)
      else baseAngle = -3 * math.pi / 4; // Long Off (Up-Left)
    } else if (d.runs == 4) {
      // 4s can be anywhere, lots of covers and square cuts
      final zone = random.nextInt(4);
      if (zone == 0) baseAngle = 0; // Cover/Point (Right)
      else if (zone == 1) baseAngle = math.pi; // Square Leg (Left)
      else if (zone == 2) baseAngle = -math.pi / 2; // Straight
      else baseAngle = math.pi / 4; // Fine Leg/Third Man (Down-Right) - actually 3rd man is upper left/right depending on hand.
    } else {
      // 1s, 2s, 3s anywhere
      baseAngle = random.nextDouble() * 2 * math.pi;
    }
    
    // Add some variance (+/- 20 degrees)
    final variance = (random.nextDouble() - 0.5) * (math.pi / 4.5);
    return baseAngle + variance;
  }



  double _getShotDistance(int runs) {
    if (runs == 6) return 0.95;
    if (runs == 4) return 0.85;
    if (runs >= 2) return 0.6;
    return 0.3;
  }

  Color _getShotColor(int runs, bool isOut) {
    if (isOut) return Colors.orange;
    if (runs == 0) return Colors.grey[300]!;
    if (runs == 1) return Colors.lightBlue;
    if (runs >= 2 && runs <= 3) return Colors.yellow;
    if (runs == 4) return Colors.purple;
    if (runs == 6) return Colors.red;
    return Colors.grey;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Animated Wagon Wheel Widget that animates the drawing of boundaries
class _AnimatedWagonWheel extends StatefulWidget {
  final List<DeliveryModel> deliveries;

  const _AnimatedWagonWheel({required this.deliveries});

  @override
  State<_AnimatedWagonWheel> createState() => _AnimatedWagonWheelState();
}

class _AnimatedWagonWheelState extends State<_AnimatedWagonWheel> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Slower animation - 3.5 seconds for smooth, professional look
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic, // Smoother curve for better visual effect
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          painter: AnimatedWagonWheelPainter(widget.deliveries, _animation.value),
        );
      },
    );
  }
}

/// Animated version of WagonWheelPainter that draws boundaries progressively
class AnimatedWagonWheelPainter extends CustomPainter {
  final List<DeliveryModel> deliveries;
  final double animationValue;

  AnimatedWagonWheelPainter(this.deliveries, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * 0.9;
    final shotOrigin = center;

    // Filter and get all valid deliveries
    final validDeliveries = deliveries.where((d) => d.isLegalBall && d.runs > 0).toList();
    final totalDeliveries = validDeliveries.length;
    
    if (totalDeliveries == 0) return;

    // Animate each boundary independently with smooth, slow progression
    for (int i = 0; i < validDeliveries.length; i++) {
      final d = validDeliveries[i];
      final angle = _getShotAngle(d);
      final distance = _getShotDistance(d.runs);
      
      // Calculate individual progress for each boundary
      // Each boundary gets its own animation window with overlap for smooth flow
      final startTime = i / totalDeliveries * 0.7; // Start earlier for overlap
      final endTime = startTime + 0.4; // Each boundary takes 40% of total animation
      
      // Calculate progress for this specific boundary
      double lineProgress = 0.0;
      if (animationValue >= startTime) {
        final boundaryProgress = ((animationValue - startTime) / (endTime - startTime)).clamp(0.0, 1.0);
        // Use easeOut curve for smooth deceleration
        lineProgress = 1 - math.pow(1 - boundaryProgress, 3).toDouble();
      }
      
      // Calculate end point based on progress
      final endX = center.dx + math.cos(angle) * distance * radius * lineProgress;
      final endY = center.dy + math.sin(angle) * distance * radius * lineProgress;
      
      final isOut = d.wicketType != null;
      final color = _getShotColor(d.runs, isOut);

      // Draw boundary line with smooth animation
      if (lineProgress > 0) {
        // Main boundary line
        final shotPaint = Paint()
          ..color = color.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isOut ? 3.5 : 2.5
          ..strokeCap = StrokeCap.round;
        
        canvas.drawLine(shotOrigin, Offset(endX, endY), shotPaint);
        
        // Animate marker appearance smoothly (appears when line is 75% complete)
        if (lineProgress >= 0.75) {
          final markerProgress = ((lineProgress - 0.75) / 0.25).clamp(0.0, 1.0);
          final markerOpacity = markerProgress;
          final markerSize = (isOut ? 4.0 : 2.5) * markerProgress;
          final markerPaint = Paint()..color = color.withOpacity(markerOpacity);
          canvas.drawCircle(Offset(endX, endY), markerSize, markerPaint);
        }
        
        // Animate glow effect for boundaries (4s and 6s) - appears when line is 60% complete
        if (d.runs >= 4 && lineProgress >= 0.6) {
          final glowProgress = ((lineProgress - 0.6) / 0.4).clamp(0.0, 1.0);
          final glowOpacity = glowProgress * 0.4; // Smooth fade in
          final glowPaint = Paint()
            ..color = color.withOpacity(glowOpacity)
            ..strokeWidth = 5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(shotOrigin, Offset(endX, endY), glowPaint);
        }
      }
    }
  }

  double _getShotAngle(DeliveryModel d) {
    final seed = d.over * 100 + d.ball + d.runs + (d.striker.length);
    final random = math.Random(seed);
    
    double baseAngle;
    
    if (d.runs == 6) {
      final zone = random.nextInt(3); 
      if (zone == 0) baseAngle = -math.pi / 2;
      else if (zone == 1) baseAngle = -math.pi / 4;
      else baseAngle = -3 * math.pi / 4;
    } else if (d.runs == 4) {
      final zone = random.nextInt(4);
      if (zone == 0) baseAngle = 0;
      else if (zone == 1) baseAngle = math.pi;
      else if (zone == 2) baseAngle = -math.pi / 2;
      else baseAngle = math.pi / 4;
    } else {
      baseAngle = random.nextDouble() * 2 * math.pi;
    }
    
    final variance = (random.nextDouble() - 0.5) * (math.pi / 4.5);
    return baseAngle + variance;
  }

  double _getShotDistance(int runs) {
    if (runs == 6) return 0.95;
    if (runs == 4) return 0.85;
    if (runs >= 2) return 0.6;
    return 0.3;
  }

  Color _getShotColor(int runs, bool isOut) {
    if (isOut) return Colors.orange;
    if (runs == 0) return Colors.grey[300]!;
    if (runs == 1) return Colors.lightBlue;
    if (runs >= 2 && runs <= 3) return Colors.yellow;
    if (runs == 4) return Colors.purple;
    if (runs == 6) return Colors.red;
    return Colors.grey;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is AnimatedWagonWheelPainter) {
      return oldDelegate.animationValue != animationValue;
    }
    return true;
  }
}

