import '../models/commentary_model.dart';
import 'dart:math';

/// New Human-like Commentary Engine
/// Generates natural, emotional commentary similar to live cricket broadcasts
class HumanCommentaryEngine {
  static final Random _random = Random();
  
  // Emotional phrases for different scenarios
  static final List<String> _boundaryPhrases = [
    'smashes it over the boundary',
    'sends it racing to the boundary',
    'finds the gap and races away to the boundary',
    'punches it through the covers to the boundary',
    'lofts it over the infield to the boundary',
    'drives it elegantly to the boundary',
    'cuts it fiercely to the boundary',
    'pulls it powerfully to the boundary',
  ];
  
  static final List<String> _sixPhrases = [
    'launches it high and handsome over the boundary',
    'sends it sailing over the ropes',
    'deposits it into the stands',
    'clears the boundary with ease',
    'hits it miles into the crowd',
    'smashes it way over the boundary',
    'sends it soaring into the stands',
  ];
  
  static final List<String> _wicketPhrases = [
    'OUT!',
    'GONE!',
    'DISMISSED!',
    'CAUGHT!',
    'BOWLED!',
    'TRAPPED!',
  ];
  
  static final List<String> _shotDescriptions = [
    'elegantly',
    'powerfully',
    'aggressively',
    'confidently',
    'skillfully',
    'uncomfortably',
    'defensively',
    'beautifully',
  ];
  
  static final List<String> _ballLengths = [
    'good length ball',
    'full length ball',
    'short of good length ball',
    'full toss',
    'yorker',
    'bouncer',
  ];
  
  static final List<String> _pitchLocations = [
    'outside off stump',
    'on middle stump',
    'on leg stump',
    'outside leg stump',
    'on off stump',
    'on the pads',
  ];
  
  static final List<String> _shotTypes = [
    'off drive',
    'cover drive',
    'straight drive',
    'cut shot',
    'pull shot',
    'sweep shot',
    'defensive shot',
    'lofted shot',
  ];
  
  static final List<String> _footPositions = [
    'front foot',
    'back foot',
  ];
  
  static final Map<String, String> _directionMap = {
    'cover': 'Deep Point',
    'point': 'Deep Point',
    'midwicket': 'Deep Midwicket',
    'straight': 'Straight',
    'square': 'Square of the Wicket',
    'fine': 'Fine Leg',
    'third': 'Third Man',
    'midoff': 'Deep Mid-Off',
    'midon': 'Deep Mid-On',
    'backwardpoint': 'Deep Backward Point',
  };

  /// Generate human-like commentary for a ball
  static String generateCommentary({
    required double over,
    required String ballType,
    required int runs,
    required String strikerName,
    required String bowlerName,
    String? wicketType,
    String? shotDirection,
    String? shotType,
    bool isExtra = false,
    String? extraType,
    int? extraRuns,
  }) {
    final overStr = over.toStringAsFixed(1).replaceAll('.0', '');
    
    // Wicket commentary
    if (ballType == 'wicket' && wicketType != null) {
      return _generateWicketCommentary(
        overStr: overStr,
        wicketType: wicketType,
        strikerName: strikerName,
        bowlerName: bowlerName,
      );
    }
    
    // Six commentary
    if (runs == 6) {
      return _generateSixCommentary(
        overStr: overStr,
        strikerName: strikerName,
        bowlerName: bowlerName,
        shotDirection: shotDirection,
        shotType: shotType,
      );
    }
    
    // Four commentary
    if (runs == 4) {
      return _generateFourCommentary(
        overStr: overStr,
        strikerName: strikerName,
        bowlerName: bowlerName,
        shotDirection: shotDirection,
        shotType: shotType,
      );
    }
    
    // Extra commentary
    if (isExtra && extraType != null) {
      return _generateExtraCommentary(
        overStr: overStr,
        extraType: extraType,
        extraRuns: extraRuns ?? 0,
        strikerName: strikerName,
        bowlerName: bowlerName,
      );
    }
    
    // Normal runs commentary
    return _generateNormalCommentary(
      overStr: overStr,
      runs: runs,
      strikerName: strikerName,
      bowlerName: bowlerName,
      shotDirection: shotDirection,
      shotType: shotType,
    );
  }
  
  static String _generateWicketCommentary({
    required String overStr,
    required String wicketType,
    required String strikerName,
    required String bowlerName,
  }) {
    final phrase = _wicketPhrases[_random.nextInt(_wicketPhrases.length)];
    
    switch (wicketType) {
      case 'Bowled':
        return '$overStr: $phrase $bowlerName cleans up $strikerName! The stumps are shattered!';
      case 'Caught':
      case 'Catch Out':
        return '$overStr: $phrase $strikerName is caught! $bowlerName strikes and the fielder takes a good catch!';
      case 'LBW':
        return '$overStr: $phrase LBW! $strikerName is trapped in front by $bowlerName!';
      case 'Run Out':
        return '$overStr: $phrase RUN OUT! Direct hit and $strikerName is short of the crease!';
      case 'Stumped':
        return '$overStr: $phrase Stumped! $strikerName is out of the crease and $bowlerName strikes!';
      default:
        return '$overStr: $phrase $strikerName dismissed by $bowlerName!';
    }
  }
  
  static String _generateSixCommentary({
    required String overStr,
    required String strikerName,
    required String bowlerName,
    String? shotDirection,
    String? shotType,
  }) {
    final phrase = _sixPhrases[_random.nextInt(_sixPhrases.length)];
    final shotDesc = _shotDescriptions[_random.nextInt(_shotDescriptions.length)];
    final ballLength = _ballLengths[_random.nextInt(_ballLengths.length)];
    final pitchLoc = _pitchLocations[_random.nextInt(_pitchLocations.length)];
    final shot = shotType ?? _shotTypes[_random.nextInt(_shotTypes.length)];
    final foot = _footPositions[_random.nextInt(_footPositions.length)];
    
    String directionText = '';
    if (shotDirection != null) {
      directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
    }
    
    return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays a $shot on the $foot, $phrase$directionText';
  }
  
  static String _generateFourCommentary({
    required String overStr,
    required String strikerName,
    required String bowlerName,
    String? shotDirection,
    String? shotType,
  }) {
    final phrase = _boundaryPhrases[_random.nextInt(_boundaryPhrases.length)];
    final shotDesc = _shotDescriptions[_random.nextInt(_shotDescriptions.length)];
    final ballLength = _ballLengths[_random.nextInt(_ballLengths.length)];
    final pitchLoc = _pitchLocations[_random.nextInt(_pitchLocations.length)];
    final shot = shotType ?? _shotTypes[_random.nextInt(_shotTypes.length)];
    final foot = _footPositions[_random.nextInt(_footPositions.length)];
    
    String directionText = '';
    if (shotDirection != null) {
      directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
    }
    
    return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays an aggressive $shot on the $foot for 4 runs$directionText';
  }
  
  static String _generateExtraCommentary({
    required String overStr,
    required String extraType,
    required int extraRuns,
    required String strikerName,
    required String bowlerName,
  }) {
    switch (extraType) {
      case 'WD':
        if (extraRuns > 1) {
          return '$overStr: Wide! $bowlerName strays down leg, $extraRuns runs to $strikerName';
        }
        return '$overStr: Wide! $bowlerName bowls wide, 1 run added';
      case 'NB':
        if (extraRuns > 1) {
          return '$overStr: No Ball! $bowlerName oversteps, $extraRuns runs to $strikerName';
        }
        return '$overStr: No Ball! $bowlerName oversteps, 1 run added';
      case 'B':
        if (extraRuns > 0) {
          return '$overStr: Byes! $extraRuns run${extraRuns > 1 ? 's' : ''} added, $strikerName and partner run well';
        }
        return '$overStr: Byes! No run, $bowlerName beats the bat';
      case 'LB':
        if (extraRuns > 0) {
          return '$overStr: Leg Byes! $extraRuns run${extraRuns > 1 ? 's' : ''} added off the pads';
        }
        return '$overStr: Leg Byes! No run, ball hits the pad';
      default:
        return '$overStr: Extra! $extraRuns run${extraRuns > 1 ? 's' : ''} added';
    }
  }
  
  static String _generateNormalCommentary({
    required String overStr,
    required int runs,
    required String strikerName,
    required String bowlerName,
    String? shotDirection,
    String? shotType,
  }) {
    final shotDesc = _shotDescriptions[_random.nextInt(_shotDescriptions.length)];
    final ballLength = _ballLengths[_random.nextInt(_ballLengths.length)];
    final pitchLoc = _pitchLocations[_random.nextInt(_pitchLocations.length)];
    final shot = shotType ?? _shotTypes[_random.nextInt(_shotTypes.length)];
    final foot = _footPositions[_random.nextInt(_footPositions.length)];
    
    if (runs == 0) {
      String directionText = '';
      if (shotDirection != null) {
        directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
      }
      return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays a $shot on the $foot, no run$directionText';
    }
    
    if (runs == 1) {
      String directionText = '';
      if (shotDirection != null) {
        directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
      }
      return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays a $shot on the $foot for a single$directionText';
    }
    
    if (runs == 2) {
      String directionText = '';
      if (shotDirection != null) {
        directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
      }
      return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays a $shot on the $foot for a couple$directionText';
    }
    
    if (runs == 3) {
      String directionText = '';
      if (shotDirection != null) {
        directionText = ' towards ${_directionMap[shotDirection.toLowerCase()] ?? shotDirection}';
      }
      return '$overStr $bowlerName bowling to $strikerName, $ballLength, pitching $pitchLoc, $strikerName $shotDesc plays a $shot on the $foot for three runs$directionText';
    }
    
    return '$overStr $bowlerName to $strikerName, $runs run${runs > 1 ? 's' : ''}';
  }
}


