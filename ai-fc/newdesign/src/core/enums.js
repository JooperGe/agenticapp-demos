// core/enums.js — 集中枚举常量（见 newdesign/04-data-schemas.md §0）

export const TeamId = { HOME: 'home', AWAY: 'away' };

export const SpeedMode = {
  STAND: 'stand', WALK: 'walk', JOG: 'jog', RUN: 'run', SPRINT: 'sprint',
};

// 各速度模式的基础速度 (m/s)，实际再按球员 pace 微调
export const SPEED_MS = {
  stand: 0, walk: 1.6, jog: 3.2, run: 5.5, sprint: 7.5,
};

export const Role = {
  GK: 'GK', CB: 'CB', LB: 'LB', RB: 'RB',
  CM: 'CM', LW: 'LW', RW: 'RW', ST: 'ST',
};

export const PhaseMain = {
  PRE_MATCH: 'PreMatch', KICKOFF: 'Kickoff', IN_PLAY: 'InPlay',
  DEAD_BALL: 'DeadBall', HALF_TIME: 'HalfTime', FULL_TIME: 'FullTime',
};

export const PhaseSub = {
  THROW_IN: 'ThrowIn', CORNER: 'Corner', GOAL_KICK: 'GoalKick',
  FREE_KICK: 'FreeKick', PENALTY: 'Penalty', KICKOFF_AFTER_GOAL: 'KickoffAfterGoal',
};

export const RestartType = {
  KICKOFF: 'kickoff', THROW_IN: 'throwIn', CORNER: 'corner',
  GOAL_KICK: 'goalKick', FREE_KICK: 'freeKick', PENALTY: 'penalty',
};

export const BoundarySide = {
  TOUCH_TOP: 'touchTop',       // y = width
  TOUCH_BOTTOM: 'touchBottom', // y = 0
  GOAL_LINE_HOME: 'goalLineHome', // x = 0   (home 防守的底线)
  GOAL_LINE_AWAY: 'goalLineAway', // x = length (away 防守的底线)
};

export const EventType = {
  MatchStarted: 'MatchStarted',
  HalfStarted: 'HalfStarted',
  HalfEnded: 'HalfEnded',
  FullTime: 'FullTime',
  PhaseChanged: 'PhaseChanged',
  KickoffAwarded: 'KickoffAwarded',
  BallOutOfPlay: 'BallOutOfPlay',
  ThrowInAwarded: 'ThrowInAwarded',
  CornerKickAwarded: 'CornerKickAwarded',
  GoalKickAwarded: 'GoalKickAwarded',
  RestartAssigned: 'RestartAssigned',
  RestartReady: 'RestartReady',
  PossessionChanged: 'PossessionChanged',
  GoalScored: 'GoalScored',
};

export const IntentType = {
  Move: 'MoveIntent',
  Kick: 'KickIntent',
  Idle: 'IdleIntent',
  Tackle: 'TackleIntent',
  Intercept: 'InterceptIntent',
};

// home 进攻 +x，away 进攻 -x
export function attackDir(teamId) {
  return teamId === TeamId.HOME ? 1 : -1;
}
export function opponentTeam(teamId) {
  return teamId === TeamId.HOME ? TeamId.AWAY : TeamId.HOME;
}
