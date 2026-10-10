import '../../data/models/training_session.dart';

/// The fixed catalogue of training courses shown on the 训练 page.
///
/// Courses are static seed data — like planets, they never re-randomise — so
/// rewards and guided steps stay identical between launches. Keeping them in
/// one `const` list means balancing (rewards / step wording) happens here
/// rather than inside the UI. `seedColor` drives each card's accent so the
/// three courses stay visually distinct.
const List<TrainingCourse> kTrainingCourses = <TrainingCourse>[
  TrainingCourse(
    id: 'walk',
    name: '轻松步行',
    subtitle: '舒缓地走一走，唤醒身体',
    durationLabel: '约 5 分钟',
    reward: 40,
    seedColor: 0xFF8EE6B0,
    steps: <String>[
      '找一处可以走动的空间',
      '放松肩膀，缓慢起步',
      '保持均匀呼吸，走动约 5 分钟',
      '慢慢停下，感受心跳',
    ],
  ),
  TrainingCourse(
    id: 'cardio',
    name: '简短有氧',
    subtitle: '让心跳微微加速',
    durationLabel: '约 8 分钟',
    reward: 70,
    seedColor: 0xFFF2C879,
    steps: <String>[
      '原地踏步热身约 1 分钟',
      '开合跳 20 次，节奏放轻松',
      '原地高抬腿 30 秒',
      '再做一组开合跳，保持呼吸',
      '放慢节奏，深呼吸恢复心率',
    ],
  ),
  TrainingCourse(
    id: 'stretch',
    name: '拉伸舒展',
    subtitle: '舒展筋骨，放松身心',
    durationLabel: '约 6 分钟',
    reward: 50,
    seedColor: 0xFF7FE3E0,
    steps: <String>[
      '缓慢转动颈部，左右各绕几圈',
      '展开双臂做肩部环绕拉伸',
      '弓步下压，拉伸大腿与小腿',
      '闭眼深呼吸，彻底放松身心',
    ],
  ),
];
