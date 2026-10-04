import 'package:flutter_test/flutter_test.dart';
import 'package:pokelens/models/condition_assessment.dart';

void main() {
  test('no reported defects is provisional Near Mint, never Mint', () {
    const result = ConditionAssessment();
    expect(result.code, 'NM');
    expect(result.label, 'Near Mint');
    expect(result.explanation, contains('vorläufig'));
    expect(result.explanation, contains('Manuelle Orientierung'));
  });

  test('small defects degrade the estimate conservatively', () {
    const light = ConditionAssessment(corners: WearLevel.light);
    expect(light.code, 'EX');
    expect(light.copyWith(edges: WearLevel.light).code, 'GD');
    expect(const ConditionAssessment(surface: WearLevel.moderate).code, 'GD');
    expect(
      const ConditionAssessment(
        corners: WearLevel.moderate,
        edges: WearLevel.moderate,
      ).code,
      'LP',
    );
  });

  test('a severe defect cannot be averaged away by perfect areas', () {
    for (final assessment in [
      const ConditionAssessment(corners: WearLevel.severe),
      const ConditionAssessment(edges: WearLevel.severe),
      const ConditionAssessment(surface: WearLevel.severe),
    ]) {
      expect(assessment.code, 'PL');
    }
  });

  test('a crease always leads to Poor', () {
    expect(const ConditionAssessment(creased: true).code, 'PO');
    expect(
      const ConditionAssessment(creased: true, edges: WearLevel.severe).label,
      'Poor',
    );
  });

  test('a worsening defect never improves the estimated grade', () {
    const order = ['NM', 'EX', 'GD', 'LP', 'PL', 'PO'];
    for (final corners in WearLevel.values) {
      for (final edges in WearLevel.values) {
        var previousRank = -1;
        for (final surface in WearLevel.values) {
          final result = ConditionAssessment(
            corners: corners,
            edges: edges,
            surface: surface,
          );
          final rank = order.indexOf(result.code);
          expect(rank, greaterThanOrEqualTo(previousRank));
          previousRank = rank;
        }
      }
    }
  });

  test('condition observations survive storage round-trip', () {
    const result = ConditionAssessment(
      corners: WearLevel.moderate,
      edges: WearLevel.light,
      creased: true,
    );
    final restored = ConditionAssessment.fromJson(result.toJson());
    expect(restored.corners, result.corners);
    expect(restored.edges, result.edges);
    expect(restored.surface, result.surface);
    expect(restored.creased, isTrue);
    expect(restored.code, result.code);
  });
}
