/// A node in the indoor navigation graph.
class MapNode {
  final String id;
  final String name;
  final int floor;
  final List<String> expectedSigns; // OCR text patterns to match
  final List<String> hazards;       // Spoken hazard warnings at this node
  final String description;

  const MapNode({
    required this.id,
    required this.name,
    required this.floor,
    required this.expectedSigns,
    required this.hazards,
    this.description = '',
  });

  factory MapNode.fromJson(Map<String, dynamic> j) => MapNode(
        id: j['id'] as String,
        name: j['name'] as String,
        floor: j['floor'] as int,
        expectedSigns:
            List<String>.from(j['expected_signs'] as List? ?? []),
        hazards: List<String>.from(j['hazards'] as List? ?? []),
        description: j['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'floor': floor,
        'expected_signs': expectedSigns,
        'hazards': hazards,
        'description': description,
      };
}
