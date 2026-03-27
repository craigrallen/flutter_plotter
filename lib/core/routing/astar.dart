import 'dart:collection';
import 'package:latlong2/latlong.dart';
import '../../data/models/vessel_profile.dart';
import '../nav/geo.dart';

class GridCell {
  final double? depth; // null = land / impassable

  const GridCell(this.depth);

  bool get isPassable => depth != null;
}

class DepthGrid {
  final List<List<GridCell>> cells;
  final LatLng origin; // top-left corner
  final double latStep; // degrees per row (negative = south)
  final double lonStep; // degrees per column (positive = east)

  const DepthGrid({
    required this.cells,
    required this.origin,
    required this.latStep,
    required this.lonStep,
  });

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells[0].length;

  GridCell? cellAt(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return null;
    return cells[row][col];
  }

  LatLng cellToLatLng(int row, int col) {
    return LatLng(
      origin.latitude + row * latStep,
      origin.longitude + col * lonStep,
    );
  }

  (int row, int col) latLngToCell(LatLng point) {
    final row = ((point.latitude - origin.latitude) / latStep).round();
    final col = ((point.longitude - origin.longitude) / lonStep).round();
    return (row.clamp(0, rows - 1), col.clamp(0, cols - 1));
  }
}

class _Node implements Comparable<_Node> {
  final int row;
  final int col;
  final double g; // cost from start
  final double f; // g + heuristic
  final _Node? parent;

  _Node(this.row, this.col, this.g, this.f, this.parent);

  @override
  int compareTo(_Node other) => f.compareTo(other.f);
}

/// Run A* pathfinding on a depth grid.
/// Returns a list of LatLng waypoints, or null if no path found.
List<LatLng>? astarSearch(
  DepthGrid grid,
  LatLng start,
  LatLng goal,
  VesselProfile vessel, {
  double safetyMargin = 0.5,
  bool preferDeepWater = false,
  void Function(double progress)? onProgress,
}) {
  final (startRow, startCol) = grid.latLngToCell(start);
  final (goalRow, goalCol) = grid.latLngToCell(goal);

  // Verify start and goal are passable
  final startCell = grid.cellAt(startRow, startCol);
  final goalCell = grid.cellAt(goalRow, goalCol);
  if (startCell == null || !startCell.isPassable) return null;
  if (goalCell == null || !goalCell.isPassable) return null;

  final minDepth = vessel.draft + safetyMargin;
  final open = PriorityQueue<_Node>();
  final closed = HashSet<int>();

  int key(int r, int c) => r * grid.cols + c;

  final goalLatLng = grid.cellToLatLng(goalRow, goalCol);

  double heuristic(int r, int c) {
    return haversineDistanceM(grid.cellToLatLng(r, c), goalLatLng);
  }

  open.add(_Node(startRow, startCol, 0, heuristic(startRow, startCol), null));
  final bestG = <int, double>{};
  int iterations = 0;
  final maxIterations = grid.rows * grid.cols * 2;

  // 8-directional neighbours
  const dirs = [
    (-1, -1), (-1, 0), (-1, 1),
    (0, -1),           (0, 1),
    (1, -1),  (1, 0),  (1, 1),
  ];

  while (open.isNotEmpty && iterations < maxIterations) {
    iterations++;
    if (onProgress != null && iterations % 500 == 0) {
      onProgress(iterations / maxIterations);
    }

    final current = open.removeFirst();

    if (current.row == goalRow && current.col == goalCol) {
      // Reconstruct path
      final path = <LatLng>[];
      _Node? node = current;
      while (node != null) {
        path.add(grid.cellToLatLng(node.row, node.col));
        node = node.parent;
      }
      return path.reversed.toList();
    }

    final ck = key(current.row, current.col);
    if (closed.contains(ck)) continue;
    closed.add(ck);

    for (final (dr, dc) in dirs) {
      final nr = current.row + dr;
      final nc = current.col + dc;

      final nk = key(nr, nc);
      if (closed.contains(nk)) continue;

      final cell = grid.cellAt(nr, nc);
      if (cell == null || !cell.isPassable) continue;
      if (cell.depth! < vessel.draft) continue; // impassable for this vessel

      // Cost: base distance + penalties
      final isDiagonal = dr != 0 && dc != 0;
      double stepCost = isDiagonal ? 1.414 : 1.0;

      // Penalise shallow water
      if (cell.depth! < minDepth) {
        stepCost *= 10.0; // heavy penalty
      } else if (cell.depth! < vessel.draft + 1.0) {
        stepCost *= 3.0; // moderate penalty
      }

      // Prefer deep water bonus
      if (preferDeepWater && cell.depth! > 10.0) {
        stepCost *= 0.8;
      }

      final g = current.g + stepCost;
      final prev = bestG[nk];
      if (prev != null && g >= prev) continue;
      bestG[nk] = g;

      final f = g + heuristic(nr, nc) * 0.01; // scale heuristic to grid units
      open.add(_Node(nr, nc, g, f, current));
    }
  }

  return null; // no path found
}

/// Priority queue implementation using a binary heap.
class PriorityQueue<T extends Comparable<T>> {
  final _heap = <T>[];

  bool get isNotEmpty => _heap.isNotEmpty;
  bool get isEmpty => _heap.isEmpty;

  void add(T item) {
    _heap.add(item);
    _bubbleUp(_heap.length - 1);
  }

  T removeFirst() {
    final first = _heap[0];
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_heap[i].compareTo(_heap[parent]) >= 0) break;
      final tmp = _heap[i];
      _heap[i] = _heap[parent];
      _heap[parent] = tmp;
      i = parent;
    }
  }

  void _bubbleDown(int i) {
    final n = _heap.length;
    while (true) {
      var smallest = i;
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      if (left < n && _heap[left].compareTo(_heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < n && _heap[right].compareTo(_heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == i) break;
      final tmp = _heap[i];
      _heap[i] = _heap[smallest];
      _heap[smallest] = tmp;
      i = smallest;
    }
  }
}
