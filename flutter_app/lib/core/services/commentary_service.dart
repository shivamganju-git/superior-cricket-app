import '../models/commentary_model.dart';

/// Service for generating ball-by-ball commentary text
class CommentaryService {
  /// Generate commentary text based on scoring event
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
        runs: runs,
      );
    }
    
    // Boundary commentary
    if (runs == 4) {
      return _generateBoundaryCommentary(
        overStr: overStr,
        strikerName: strikerName,
        bowlerName: bowlerName,
        shotDirection: shotDirection,
        shotType: shotType,
      );
    }
    
    if (runs == 6) {
      return _generateSixCommentary(
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
    required int runs,
  }) {
    // CricHeroes style: "15.2: OUT! Akash to Utkarsh Pandita, caught at deep cover"
    String wicketText = '';
    switch (wicketType) {
      case 'Bowled':
        wicketText = 'OUT! Bowled! $bowlerName cleans him up';
        break;
      case 'Caught':
      case 'Catch Out':
        wicketText = 'OUT! $bowlerName to $strikerName, caught';
        break;
      case 'LBW':
        wicketText = 'OUT! LBW! $strikerName trapped in front by $bowlerName';
        break;
      case 'Run Out':
        wicketText = 'OUT! RUN OUT! Direct hit from point';
        break;
      case 'Stumped':
        wicketText = 'OUT! Stumped! $strikerName out of the crease, $bowlerName strikes';
        break;
      case 'Hit Wicket':
        wicketText = 'OUT! Hit Wicket! $strikerName disturbs the stumps';
        break;
      case 'Retired Hurt':
        wicketText = 'Retired Hurt! $strikerName walks off';
        break;
      default:
        wicketText = 'OUT! $strikerName dismissed by $bowlerName';
    }
    
    String runsText = runs > 0 ? '. $runs run${runs > 1 ? 's' : ''} scored' : '';
    return '$overStr: $wicketText$runsText';
  }
  
  static String _generateBoundaryCommentary({
    required String overStr,
    required String strikerName,
    required String bowlerName,
    String? shotDirection,
    String? shotType,
  }) {
    // Enhanced emotional commentary for boundaries
    final emotionalPhrases = [
      'plays an aggressive',
      'strikes a powerful',
      'hits a magnificent',
      'smashes a brilliant',
      'cracks a stunning',
    ];
    final randomPhrase = emotionalPhrases[DateTime.now().millisecond % emotionalPhrases.length];
    
    String directionText = '';
    if (shotDirection != null) {
      directionText = ' towards ${_formatDirection(shotDirection)}';
    }
    
    return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} for 4 runs$directionText';
  }
  
  static String _generateSixCommentary({
    required String overStr,
    required String strikerName,
    required String bowlerName,
    String? shotDirection,
    String? shotType,
  }) {
    // Enhanced emotional commentary for sixes
    final emotionalPhrases = [
      'launches a massive',
      'sends it soaring with a',
      'deposits it into the stands with a',
      'clears the boundary with a thunderous',
      'hits a colossal',
    ];
    final randomPhrase = emotionalPhrases[DateTime.now().millisecond % emotionalPhrases.length];
    
    String directionText = '';
    if (shotDirection != null) {
      directionText = ' towards ${_formatDirection(shotDirection)}';
    }
    
    return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} for SIX runs$directionText';
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
    // Enhanced emotional commentary
    final emotionalPhrases = [
      'uncomfortably plays',
      'aggressively plays',
      'confidently plays',
      'elegantly plays',
      'powerfully plays',
      'skillfully plays',
    ];
    final randomPhrase = emotionalPhrases[(runs * 7) % emotionalPhrases.length];
    
    // CricHeroes style with emotional commentary
    if (runs == 0) {
      final directionText = shotDirection != null ? ' towards ${_formatDirection(shotDirection)}' : '';
      return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} on the ${_getFootPosition()}, no run$directionText';
    }
    
    if (runs == 1) {
      final directionText = shotDirection != null ? ' towards ${_formatDirection(shotDirection)}' : '';
      return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} for a single$directionText';
    }
    
    if (runs == 2) {
      final directionText = shotDirection != null ? ' towards ${_formatDirection(shotDirection)}' : '';
      return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} for a couple$directionText';
    }
    
    if (runs == 3) {
      final directionText = shotDirection != null ? ' towards ${_formatDirection(shotDirection)}' : '';
      return '$overStr $bowlerName bowling to $strikerName, ${_getBallLength()}, pitching ${_getPitchLocation()}, $strikerName $randomPhrase ${_getShotType(shotType)} for three runs$directionText';
    }
    
    return '$overStr $bowlerName to $strikerName, $runs run${runs > 1 ? 's' : ''}';
  }

  static String _getBallLength() {
    final lengths = ['good length ball', 'full length ball', 'short of good length ball', 'full toss', 'yorker'];
    return lengths[DateTime.now().millisecond % lengths.length];
  }

  static String _getPitchLocation() {
    final locations = ['outside off stump', 'on middle stump', 'on leg stump', 'outside leg stump', 'on off stump'];
    return locations[DateTime.now().millisecond % locations.length];
  }

  static String _getShotType(String? shotType) {
    if (shotType != null) {
      return shotType;
    }
    final shots = ['off drive', 'cut shot', 'pull shot', 'defensive shot', 'straight drive', 'cover drive'];
    return shots[DateTime.now().millisecond % shots.length];
  }

  static String _getFootPosition() {
    final positions = ['front foot', 'back foot'];
    return positions[DateTime.now().millisecond % positions.length];
  }

  static String _formatDirection(String? direction) {
    if (direction == null) return '';
    final directionMap = {
      'cover': 'Short Extra Covers',
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
    return directionMap[direction.toLowerCase()] ?? direction;
  }
}

