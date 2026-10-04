enum WearLevel { none, light, moderate, severe }

extension WearLevelLabel on WearLevel {
  String get label => switch (this) {
    WearLevel.none => 'Keine',
    WearLevel.light => 'Leicht',
    WearLevel.moderate => 'Deutlich',
    WearLevel.severe => 'Stark',
  };
}

/// Conservative manual estimate based on defects the collector has inspected.
/// This does not represent automatic photo grading or a grading certificate.
class ConditionAssessment {
  const ConditionAssessment({
    this.corners = WearLevel.none,
    this.edges = WearLevel.none,
    this.surface = WearLevel.none,
    this.creased = false,
  });

  final WearLevel corners;
  final WearLevel edges;
  final WearLevel surface;
  final bool creased;

  String get code {
    if (creased) return 'PO';
    final wear = [corners, edges, surface];
    if (wear.contains(WearLevel.severe)) return 'PL';
    final total = wear.fold(0, (sum, level) => sum + level.index);
    if (total >= 4) return 'LP';
    if (total >= 2) return 'GD';
    if (total == 1) return 'EX';
    return 'NM';
  }

  String get label => switch (code) {
    'PO' => 'Poor',
    'PL' => 'Played',
    'LP' => 'Light Played',
    'GD' => 'Good',
    'EX' => 'Excellent',
    _ => 'Near Mint',
  };

  String get explanation {
    final reason = switch (code) {
      'PO' =>
        'Knicke oder Falten führen zu einer vorsichtigen Poor-Einstufung.',
      'PL' => 'Starke Spuren an mindestens einem Bereich sprechen für Played.',
      'LP' => 'Mehrere deutliche Gebrauchsspuren sprechen für Light Played.',
      'GD' =>
        'Deutliche oder mehrere leichte Gebrauchsspuren sprechen für Good.',
      'EX' =>
        'Ein Bereich zeigt leichte Gebrauchsspuren: voraussichtlich Excellent.',
      _ =>
        'Du hast keine sichtbaren Gebrauchsspuren angegeben: vorläufig Near Mint.',
    };
    return '$reason Manuelle Orientierung, kein zertifiziertes Grading. '
        'Vorder- und Rückseite sowie Oberfläche im Streiflicht prüfen.';
  }

  ConditionAssessment copyWith({
    WearLevel? corners,
    WearLevel? edges,
    WearLevel? surface,
    bool? creased,
  }) => ConditionAssessment(
    corners: corners ?? this.corners,
    edges: edges ?? this.edges,
    surface: surface ?? this.surface,
    creased: creased ?? this.creased,
  );

  Map<String, dynamic> toJson() => {
    'corners': corners.name,
    'edges': edges.name,
    'surface': surface.name,
    'creased': creased,
  };

  factory ConditionAssessment.fromJson(Map<String, dynamic> json) {
    WearLevel levelFor(String key) => WearLevel.values.firstWhere(
      (value) => value.name == json[key],
      orElse: () => WearLevel.none,
    );
    return ConditionAssessment(
      corners: levelFor('corners'),
      edges: levelFor('edges'),
      surface: levelFor('surface'),
      creased: json['creased'] == true,
    );
  }
}
