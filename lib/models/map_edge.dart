/// A directed edge between two map nodes.
class MapEdge {
  final String from;
  final String to;
  final int steps;        // approximate steps to walk
  final double heading;   // compass heading in degrees (0=N, 90=E, 180=S, 270=W)

  const MapEdge({
    required this.from,
    required this.to,
    required this.steps,
    required this.heading,
  });

  factory MapEdge.fromJson(Map<String, dynamic> j) => MapEdge(
        from: j['from'] as String,
        to: j['to'] as String,
        steps: j['steps'] as int,
        heading: (j['heading'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'steps': steps,
        'heading': heading,
      };
}
