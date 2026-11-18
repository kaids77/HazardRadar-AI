import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/hazard_category.dart';
import 'package:hazardradarai/models/triage_result.dart';
import 'package:hazardradarai/services/triage_service.dart';

Future<String> _category(String note) async => (await const KeywordTriageService().classify(note)).category;

void main() {
  test('classifies English notes into the fixed categories', () async {
    expect(await _category('Live wire sparking near the gate'), HazardCategory.electrical);
    expect(await _category('Street flooded after the rain'), HazardCategory.flooding);
    expect(await _category('Streetlight is out on this corner'), HazardCategory.lighting);
    expect(await _category('Deep pothole in the right lane'), HazardCategory.pothole);
    expect(await _category('Fallen tree blocking the sidewalk'), HazardCategory.obstruction);
    expect(await _category('Something weird here'), HazardCategory.other);
  });

  test('classifies Tagalog and Cebuano notes', () async {
    expect(await _category('May kuryente sa kable, delikado'), HazardCategory.electrical);
    expect(await _category('Baha na dito sa kanto'), HazardCategory.flooding);
    expect(await _category('Patay ang ilaw sa kalye'), HazardCategory.lighting);
    expect(await _category('Walay suga diri sa dalan'), HazardCategory.lighting);
    expect(await _category('Malaking butas sa daan'), HazardCategory.pothole);
    expect(await _category('Dako nga lungag sa karsada'), HazardCategory.pothole);
    expect(await _category('Natumba ang puno sa daan'), HazardCategory.obstruction);
  });

  test('matches whole words only', () async {
    // "bahay" (house) must not count as "baha" (flood), "whole" must not count as "hole".
    expect(await _category('Sa harap ng bahay'), HazardCategory.other);
    expect(await _category('The whole area'), HazardCategory.other);
  });

  test('higher-risk categories win when several match', () async {
    expect(await _category('Sparking wire in the flood water'), HazardCategory.electrical);
  });

  test('keyword results are marked as not AI processed', () async {
    final result = await const KeywordTriageService().classify('pothole');
    expect(result.aiProcessed, isFalse);
    expect(TriageResult.riskLevels, contains(result.riskLevel));
  });

  test('AI results map unknown categories to Other and default to AI processed', () {
    final result = TriageResult.tryFromJson({
      'category': 'Road',
      'riskLevel': 'Medium',
      'aiSummary': 'Crack.',
      'recommendedAction': 'Patch.',
    });
    expect(result?.category, HazardCategory.other);
    expect(result?.aiProcessed, isTrue);
    expect(
      TriageResult.tryFromJson({
        'category': 'pothole',
        'riskLevel': 'Low',
        'aiSummary': 'Hole.',
        'recommendedAction': 'Patch.',
      })?.category,
      HazardCategory.pothole,
    );
  });
}
