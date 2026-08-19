// Port of `MultiWindowLayouts.kt` from `features/hub`.

/// A single slot position within a layout grid (rows × cols, with spans).
class SlotPos {
  final int index;
  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  const SlotPos(this.index, this.row, this.col, this.rowSpan, this.colSpan);
}

/// A named multi-window arrangement of up to 9 video slots.
enum MultiWindowLayout {
  v1Full('1'),
  v2Split('1\u00D72'),
  v2Stack('2\u00D71'),
  v3Stack('3 vert'),
  v3Top1Bot2('1+2'),
  v3Left2Right1('2+1'),
  v3Horiz('1\u00D73'),
  v3Top2Bot1('2+1v'),
  v3Left1Right2('1+2h'),
  v4Grid('2\u00D72'),
  v41_2_1('1-2-1'),
  v4Horiz('1\u00D74'),
  v4Vert('4 vert'),
  v4Left1Right3('1+3'),
  v4Left3Right1('3+1'),
  v42_1_1('2-1-1'),
  v41_1_2('1-1-2'),
  v5Grid4Bot1('4+1'),
  v5Top1Bot4('1+4'),
  v5Left3Right2('3+2'),
  v5Horiz('1\u00D75'),
  v5Top2Bot3('2+3'),
  v5Top1Grid4('1+2\u00D72'),
  v53Left2Right('3+2v'),
  v63x2('3\u00D72'),
  v62x3('2\u00D73'),
  v61_2_2_1('1-2-2-1'),
  v6Horiz('1\u00D76'),
  v6Vert('6 vert'),
  v6Grid4_2Row('4+2'),
  v63Row_2Row('3+3'),
  v71_3_3('1-3-3'),
  v7Top1Bot6('1+6'),
  v73x2Plus1('3\u00D72+1'),
  v72x3Plus1('2\u00D73+1'),
  v7Left3Grid4('1+3+3'),
  v7Asymm('7 asym'),
  v8Grid4x2('4\u00D72'),
  v82x4('2\u00D74'),
  v81_3_3_1('1-3-3-1'),
  v83x2Plus2('3\u00D72+2'),
  v82x3Plus1x2('2\u00D73+1x2'),
  v8Grid4_2RowPlus1('4+2+1'),
  v9Grid3x3('3\u00D73'),
  v9Grid3x3Center('3\u00D73+'),
  v93x2Plus3x1('3\u00D72+3'),
  v92x3Plus3x1('2\u00D73+3');

  const MultiWindowLayout(this.label);

  final String label;
}

List<MultiWindowLayout> getValidLayouts(
  int count,
  bool isPortrait,
  bool isTablet,
) {
  switch (count) {
    case 1:
      return const [MultiWindowLayout.v1Full];
    case 2:
      return const [
        MultiWindowLayout.v2Split,
        MultiWindowLayout.v2Stack,
      ];
    case 3:
      return [
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v3Top1Bot2,
          MultiWindowLayout.v3Top2Bot1,
          MultiWindowLayout.v3Stack,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v3Horiz,
          MultiWindowLayout.v3Left1Right2,
          MultiWindowLayout.v3Left2Right1,
        ],
      ];
    case 4:
      return [
        MultiWindowLayout.v4Grid,
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v4Vert,
          MultiWindowLayout.v41_2_1,
          MultiWindowLayout.v42_1_1,
          MultiWindowLayout.v41_1_2,
          MultiWindowLayout.v4Left3Right1,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v4Horiz,
          MultiWindowLayout.v4Left1Right3,
        ],
      ];
    case 5:
      return [
        MultiWindowLayout.v5Grid4Bot1,
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v5Top1Bot4,
          MultiWindowLayout.v5Top1Grid4,
          MultiWindowLayout.v5Top2Bot3,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v5Horiz,
          MultiWindowLayout.v5Left3Right2,
          MultiWindowLayout.v53Left2Right,
        ],
      ];
    case 6:
      return [
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v63x2,
          MultiWindowLayout.v61_2_2_1,
          MultiWindowLayout.v6Vert,
          MultiWindowLayout.v63Row_2Row,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v62x3,
          MultiWindowLayout.v6Horiz,
          MultiWindowLayout.v6Grid4_2Row,
        ],
      ];
    case 7:
      return [
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v71_3_3,
          MultiWindowLayout.v7Top1Bot6,
          MultiWindowLayout.v7Left3Grid4,
          MultiWindowLayout.v7Asymm,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v73x2Plus1,
          MultiWindowLayout.v72x3Plus1,
        ],
      ];
    case 8:
      return [
        if (isPortrait || isTablet) ...[
          MultiWindowLayout.v8Grid4x2,
          MultiWindowLayout.v81_3_3_1,
          MultiWindowLayout.v8Grid4_2RowPlus1,
        ],
        if (!isPortrait || isTablet) ...[
          MultiWindowLayout.v82x4,
          MultiWindowLayout.v83x2Plus2,
          MultiWindowLayout.v82x3Plus1x2,
        ],
      ];
    case 9:
      return [
        MultiWindowLayout.v9Grid3x3,
        if (isTablet) ...[
          MultiWindowLayout.v9Grid3x3Center,
          MultiWindowLayout.v93x2Plus3x1,
          MultiWindowLayout.v92x3Plus3x1,
        ],
      ];
    default:
      return const [];
  }
}

MultiWindowLayout defaultLayout(
  int count,
  bool isPortrait,
  bool isTablet,
) {
  final layouts = getValidLayouts(count, isPortrait, isTablet);
  return layouts.isEmpty ? MultiWindowLayout.v1Full : layouts.first;
}

List<SlotPos> calculateSlots(MultiWindowLayout layout, int count) {
  final slots = switch (layout) {
    MultiWindowLayout.v1Full => const [
        SlotPos(0, 0, 0, 1, 1),
      ],
    MultiWindowLayout.v2Split => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
      ],
    MultiWindowLayout.v2Stack => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
      ],
    MultiWindowLayout.v3Stack => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
      ],
    MultiWindowLayout.v3Top1Bot2 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
      ],
    MultiWindowLayout.v3Left2Right1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 0, 1, 2, 1),
      ],
    MultiWindowLayout.v3Horiz => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
      ],
    MultiWindowLayout.v3Top2Bot1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 2),
      ],
    MultiWindowLayout.v3Left1Right2 => const [
        SlotPos(0, 0, 0, 2, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
      ],
    MultiWindowLayout.v4Grid => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
      ],
    MultiWindowLayout.v41_2_1 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 0, 1, 2),
      ],
    MultiWindowLayout.v4Horiz => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 0, 3, 1, 1),
      ],
    MultiWindowLayout.v4Vert => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 3, 0, 1, 1),
      ],
    MultiWindowLayout.v4Left1Right3 => const [
        SlotPos(0, 0, 0, 3, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v4Left3Right1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 0, 1, 3, 1),
      ],
    MultiWindowLayout.v42_1_1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 2),
        SlotPos(3, 2, 0, 1, 2),
      ],
    MultiWindowLayout.v41_1_2 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 2),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v5Grid4Bot1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 2),
      ],
    MultiWindowLayout.v5Top1Bot4 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 0, 1, 1),
        SlotPos(4, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v5Left3Right2 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 0, 1, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
      ],
    MultiWindowLayout.v5Horiz => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 0, 3, 1, 1),
        SlotPos(4, 0, 4, 1, 1),
      ],
    MultiWindowLayout.v5Top2Bot3 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 1, 2, 1, 1),
      ],
    MultiWindowLayout.v5Top1Grid4 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 0, 1, 1),
        SlotPos(4, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v53Left2Right => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 0, 1, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
      ],
    MultiWindowLayout.v63x2 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v62x3 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
      ],
    MultiWindowLayout.v61_2_2_1 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 0, 1, 1),
        SlotPos(4, 2, 1, 1, 1),
        SlotPos(5, 3, 0, 1, 2),
      ],
    MultiWindowLayout.v6Horiz => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 0, 3, 1, 1),
        SlotPos(4, 0, 4, 1, 1),
        SlotPos(5, 0, 5, 1, 1),
      ],
    MultiWindowLayout.v6Vert => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 2, 0, 1, 1),
        SlotPos(3, 3, 0, 1, 1),
        SlotPos(4, 4, 0, 1, 1),
        SlotPos(5, 5, 0, 1, 1),
      ],
    MultiWindowLayout.v6Grid4_2Row || MultiWindowLayout.v63Row_2Row => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v71_3_3 => const [
        SlotPos(0, 0, 0, 1, 3),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 1, 2, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 2, 2, 1, 1),
      ],
    MultiWindowLayout.v7Top1Bot6 => const [
        SlotPos(0, 0, 0, 1, 2),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 2, 0, 1, 1),
        SlotPos(4, 2, 1, 1, 1),
        SlotPos(5, 3, 0, 1, 1),
        SlotPos(6, 3, 1, 1, 1),
      ],
    MultiWindowLayout.v73x2Plus1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 3),
      ],
    MultiWindowLayout.v72x3Plus1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 3, 0, 1, 2),
      ],
    MultiWindowLayout.v7Left3Grid4 => const [
        SlotPos(0, 0, 0, 3, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 1, 2, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 2, 2, 1, 1),
      ],
    MultiWindowLayout.v7Asymm => const [
        SlotPos(0, 0, 0, 2, 2),
        SlotPos(1, 0, 2, 1, 1),
        SlotPos(2, 1, 2, 1, 1),
        SlotPos(3, 2, 0, 1, 1),
        SlotPos(4, 2, 1, 1, 1),
        SlotPos(5, 2, 2, 1, 1),
      ],
    MultiWindowLayout.v8Grid4x2 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 3, 0, 1, 1),
        SlotPos(7, 3, 1, 1, 1),
      ],
    MultiWindowLayout.v82x4 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 0, 3, 1, 1),
        SlotPos(4, 1, 0, 1, 1),
        SlotPos(5, 1, 1, 1, 1),
        SlotPos(6, 1, 2, 1, 1),
        SlotPos(7, 1, 3, 1, 1),
      ],
    MultiWindowLayout.v81_3_3_1 => const [
        SlotPos(0, 0, 0, 1, 3),
        SlotPos(1, 1, 0, 1, 1),
        SlotPos(2, 1, 1, 1, 1),
        SlotPos(3, 1, 2, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 2, 2, 1, 1),
        SlotPos(7, 3, 0, 1, 3),
      ],
    MultiWindowLayout.v83x2Plus2 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 1),
        SlotPos(7, 2, 1, 1, 1),
      ],
    MultiWindowLayout.v82x3Plus1x2 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 3),
      ],
    MultiWindowLayout.v8Grid4_2RowPlus1 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 1, 0, 1, 1),
        SlotPos(3, 1, 1, 1, 1),
        SlotPos(4, 2, 0, 1, 1),
        SlotPos(5, 2, 1, 1, 1),
        SlotPos(6, 3, 0, 1, 1),
        SlotPos(7, 3, 1, 1, 1),
      ],
    MultiWindowLayout.v9Grid3x3 => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 1),
        SlotPos(7, 2, 1, 1, 1),
        SlotPos(8, 2, 2, 1, 1),
      ],
    MultiWindowLayout.v9Grid3x3Center => const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 2, 2),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 1),
        SlotPos(7, 2, 1, 1, 1),
        SlotPos(8, 2, 2, 1, 1),
      ],
    MultiWindowLayout.v93x2Plus3x1 || MultiWindowLayout.v92x3Plus3x1 =>
      const [
        SlotPos(0, 0, 0, 1, 1),
        SlotPos(1, 0, 1, 1, 1),
        SlotPos(2, 0, 2, 1, 1),
        SlotPos(3, 1, 0, 1, 1),
        SlotPos(4, 1, 1, 1, 1),
        SlotPos(5, 1, 2, 1, 1),
        SlotPos(6, 2, 0, 1, 1),
        SlotPos(7, 2, 1, 1, 1),
        SlotPos(8, 2, 2, 1, 1),
      ],
  };
  return slots.take(count).toList();
}