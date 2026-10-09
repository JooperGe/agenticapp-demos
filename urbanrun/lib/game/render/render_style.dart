import 'package:flutter/material.dart';

/// Centralized palette for the procedural city.
///
/// Each element renderer takes a [RenderStyle] instead of hard-coding colors,
/// so a different look can be dropped in by swapping the style — or a single
/// element re-skinned by replacing one palette — without touching geometry.
class RenderStyle {
  const RenderStyle({
    required this.block,
    required this.road,
    required this.building,
    required this.tree,
    required this.prop,
    required this.marker,
  });

  final BlockPalette block;
  final RoadPalette road;
  final BuildingPalette building;
  final TreePalette tree;
  final PropPalette prop;
  final MarkerPalette marker;

  /// Reproduces the original demo colors exactly.
  static const RenderStyle classic = RenderStyle(
    block: BlockPalette.classic,
    road: RoadPalette.classic,
    building: BuildingPalette.classic,
    tree: TreePalette.classic,
    prop: PropPalette.classic,
    marker: MarkerPalette.classic,
  );
}

/// Street-level ground, interior floors and the park flowerbed.
class BlockPalette {
  const BlockPalette({
    required this.streetGround,
    required this.interiorGround,
    required this.interiorFloor,
    required this.flowerbed,
    required this.flowerPrimary,
    required this.flowerAccent,
  });

  final Color streetGround;
  final Color interiorGround;
  final Color interiorFloor;
  final Color flowerbed;
  final Color flowerPrimary;
  final Color flowerAccent;

  static const BlockPalette classic = BlockPalette(
    streetGround: Color(0xFF6E9B73),
    interiorGround: Color(0xFFD8C9A8),
    interiorFloor: Color(0xFFE8D8B6),
    flowerbed: Color(0xFF557A5F),
    flowerPrimary: Color(0xFFF1B66D),
    flowerAccent: Color(0xFFEE7E87),
  );
}

/// Pavement, road surface, lane markings and zebra crossings.
class RoadPalette {
  const RoadPalette({
    required this.pavement,
    required this.surface,
    required this.laneMarking,
    required this.crossing,
  });

  final Color pavement;
  final Color surface;
  final Color laneMarking;
  final Color crossing;

  static const RoadPalette classic = RoadPalette(
    pavement: Color(0xFFB8B7A4),
    surface: Color(0xFF566B77),
    laneMarking: Color(0xFF78888C),
    crossing: Color(0xFFDCE2D2),
  );
}

/// Building walls, roofs, per-building roof accents and signage text.
class BuildingPalette {
  const BuildingPalette({
    required this.interiorRoof,
    required this.streetWallLight,
    required this.interiorWallLight,
    required this.streetWallShadow,
    required this.interiorWallShadow,
    required this.label,
    required this.coffeeRoof,
    required this.marketRoof,
    required this.thirdRoof,
    required this.defaultRoof,
  });

  final Color interiorRoof;
  final Color streetWallLight;
  final Color interiorWallLight;
  final Color streetWallShadow;
  final Color interiorWallShadow;
  final Color label;
  final Color coffeeRoof;
  final Color marketRoof;
  final Color thirdRoof;
  final Color defaultRoof;

  static const BuildingPalette classic = BuildingPalette(
    interiorRoof: Color(0xFFC7A87A),
    streetWallLight: Color(0xFFBD8A62),
    interiorWallLight: Color(0xFFD4B78B),
    streetWallShadow: Color(0xFF805A4B),
    interiorWallShadow: Color(0xFFAA8967),
    label: Color(0xFFECE1C9),
    coffeeRoof: Color(0xFFD39A67),
    marketRoof: Color(0xFFA6B8A0),
    thirdRoof: Color(0xFFC48C83),
    defaultRoof: Color(0xFFB59B7A),
  );
}

/// Tree canopy and trunk.
class TreePalette {
  const TreePalette({
    required this.canopyPrimary,
    required this.canopySecondary,
    required this.trunk,
  });

  final Color canopyPrimary;
  final Color canopySecondary;
  final Color trunk;

  static const TreePalette classic = TreePalette(
    canopyPrimary: Color(0xFF2E654F),
    canopySecondary: Color(0xFF3E8059),
    trunk: Color(0xFF72513A),
  );
}

/// Street and interior decoration props (lamp, bench, car, counter, …).
class PropPalette {
  const PropPalette({
    required this.lampPole,
    required this.lampLight,
    required this.bench,
    required this.carWheel,
    required this.counterTop,
    required this.tableLeg,
    required this.shelf,
    required this.shelfBoard,
    required this.coffeeAccent,
    required this.storeAccent,
  });

  final Color lampPole;
  final Color lampLight;
  final Color bench;
  final Color carWheel;
  final Color counterTop;
  final Color tableLeg;
  final Color shelf;
  final Color shelfBoard;
  final Color coffeeAccent;
  final Color storeAccent;

  static const PropPalette classic = PropPalette(
    lampPole: Color(0xFF27343D),
    lampLight: Color(0xFFFFD68A),
    bench: Color(0xFF8C5E3E),
    carWheel: Color(0xFF303941),
    counterTop: Color(0xFFE5D6B6),
    tableLeg: Color(0xFF795441),
    shelf: Color(0xFF6A7D83),
    shelfBoard: Color(0xFFD4B36E),
    coffeeAccent: Color(0xFFB7784C),
    storeAccent: Color(0xFF648E9C),
  );
}

/// Entrance diamond markers drawn by the compositor.
class MarkerPalette {
  const MarkerPalette({required this.entrance, required this.entranceCore});

  final Color entrance;
  final Color entranceCore;

  static const MarkerPalette classic = MarkerPalette(
    entrance: Color(0xFF65D5B3),
    entranceCore: Color(0xFF23353B),
  );
}
