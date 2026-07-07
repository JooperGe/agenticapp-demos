/**
 * AI FC - 球员智能体决策系统
 * 每个球员都是一个独立的决策智能体
 */

class PlayerAgent {
  constructor(playerId, attributes, position, formation) {
    this.playerId = playerId;
    this.attributes = attributes; // 传球精度、视野、速度等
    this.state = {
      position: position,
      velocity: { x: 0, y: 0 },
      fatigue: 0,
      mentalState: 50,
      injury: 0
    };
    this.formation = formation; // 位置编号
    this.ballOwner = false;
  }

  /**
   * 每一帧的决策循环
   * 输入：当前环境状态
   * 输出：这一帧要执行的动作
   */
  makeDecision(gameState, visibleEnvironment, tacticalInfo) {
    // Step 1: 评估形势
    const situation = this.assessSituation(gameState, visibleEnvironment);

    // Step 2: 根据形势匹配决策规则
    const applicableRules = this.matchRules(situation, tacticalInfo);

    // Step 3: 对每个规则评估成功概率
    const scoredOptions = applicableRules.map(rule => ({
      rule,
      successRate: this.calculateSuccessRate(rule, situation),
      expectedValue: this.calculateExpectedValue(rule, situation)
    }));

    // Step 4: 选择期望价值最高的动作
    const bestOption = scoredOptions.sort((a, b) => b.expectedValue - a.expectedValue)[0];

    if (!bestOption) {
      // 没有匹配规则，返回默认动作
      return this.getDefaultAction(situation);
    }

    // Step 5: 返回决策动作
    return {
      playerId: this.playerId,
      actionType: bestOption.rule.action,
      target: this.selectTarget(bestOption.rule, visibleEnvironment),
      parameters: this.generateActionParameters(bestOption.rule, situation),
      expectedSuccessRate: bestOption.successRate
    };
  }

  /**
   * 评估当前形势
   */
  assessSituation(gameState, visibleEnvironment) {
    return {
      iHaveBall: this.ballOwner,
      myPosition: this.state.position,
      myVelocity: this.state.velocity,
      visibleTeammates: visibleEnvironment.teammates,
      visibleOpponents: visibleEnvironment.opponents,
      ballPosition: gameState.ballPosition,
      ballOwner: gameState.ballOwner,
      matchPhase: gameState.matchPhase,
      score: gameState.score,
      time: gameState.time
    };
  }

  /**
   * 根据形势匹配决策规则
   * 规则来自 config/4-decision/decision-rules.json
   */
  matchRules(situation, tacticalInfo) {
    const rules = [
      // 有球的情况
      ...(situation.iHaveBall ? this.getHasBallRules(situation) : []),
      // 无球的情况
      ...(!situation.iHaveBall ? this.getNoBallRules(situation) : []),
      // 防守的情况
      ...this.getDefensiveRules(situation)
    ];

    return rules.filter(rule => rule.conditionMet(situation, tacticalInfo));
  }

  /**
   * 有球时的规则
   */
  getHasBallRules(situation) {
    return [
      {
        id: "clear-pass",
        name: "有明确传球目标",
        conditionMet: (sit, tac) => sit.iHaveBall && sit.visibleTeammates.some(t => t.isOpen),
        action: "pass"
      },
      {
        id: "shooting-chance",
        name: "射门机会",
        conditionMet: (sit, tac) => sit.iHaveBall && this.isInShootingRange(sit) && sit.visibleOpponents.length < 3,
        action: "shoot"
      },
      {
        id: "dribble-space",
        name: "盘带推进",
        conditionMet: (sit, tac) => sit.iHaveBall && this.hasOpenSpace(sit),
        action: "dribble"
      },
      {
        id: "safe-pass",
        name: "安全传球",
        conditionMet: (sit, tac) => sit.iHaveBall && sit.visibleOpponents.some(o => o.distance < 5),
        action: "pass"
      }
    ];
  }

  /**
   * 无球时的规则
   */
  getNoBallRules(situation) {
    return [
      {
        id: "run-to-space",
        name: "跑位到空档",
        conditionMet: (sit, tac) => !sit.iHaveBall && this.hasOpenSpace(sit),
        action: "runToPosition"
      },
      {
        id: "support-teammate",
        name: "接应队友",
        conditionMet: (sit, tac) => !sit.iHaveBall && sit.visibleTeammates.some(t => t.hasBall),
        action: "runToPosition"
      }
    ];
  }

  /**
   * 防守规则
   */
  getDefensiveRules(situation) {
    return [
      {
        id: "mark-opponent",
        name: "盯防对手",
        conditionMet: (sit, tac) => sit.visibleOpponents.some(o => o.distance < 10),
        action: "defend"
      },
      {
        id: "tackle-opportunity",
        name: "抢断机会",
        conditionMet: (sit, tac) => sit.visibleOpponents.some(o => o.hasBall && o.distance < 3),
        action: "tackle"
      },
      {
        id: "cover-gap",
        name: "补防",
        conditionMet: (sit, tac) => this.defensiveGapNearby(sit),
        action: "moveToDefensiveGap"
      }
    ];
  }

  /**
   * 计算动作的成功率
   */
  calculateSuccessRate(rule, situation) {
    const weights = rule.weights || {};

    switch (rule.action) {
      case "pass":
        return this.calculatePassSuccessRate(situation, weights);
      case "shoot":
        return this.calculateShootSuccessRate(situation, weights);
      case "dribble":
        return this.calculateDribbleSuccessRate(situation, weights);
      case "tackle":
        return this.calculateTackleSuccessRate(situation, weights);
      default:
        return 0.5; // 默认50%
    }
  }

  /**
   * 传球成功率计算
   */
  calculatePassSuccessRate(situation, weights) {
    const baseRate = this.attributes.passing * 0.01; // 0-1
    const mentalMod = 1 + (this.state.mentalState - 50) * 0.01; // 心理影响
    const fatigueMod = 1 - this.state.fatigue * 0.01; // 疲劳影响
    const distanceMod = 1 - (situation.targetDistance || 20) / 100; // 距离影响

    return Math.max(0, Math.min(1, baseRate * mentalMod * fatigueMod * distanceMod));
  }

  /**
   * 射门成功率计算
   */
  calculateShootSuccessRate(situation, weights) {
    const baseRate = this.attributes.shooting * 0.01;
    const mentalMod = 1 + (this.state.mentalState - 50) * 0.01;
    const fatigueMod = 1 - this.state.fatigue * 0.01;
    const distanceMod = 1 - Math.abs(situation.goalDistance - 12) / 30; // 距离12米最优

    return Math.max(0, Math.min(1, baseRate * mentalMod * fatigueMod * distanceMod));
  }

  /**
   * 计算期望价值
   */
  calculateExpectedValue(rule, situation) {
    const successRate = this.calculateSuccessRate(rule, situation);
    const riskFactor = 1 - this.state.mentalState / 100; // 心理差异导致风险承受度不同

    // 不同动作的基础价值
    const baseValue = {
      pass: 1,
      shoot: 5,
      dribble: 0.5,
      defend: 2,
      tackle: 3
    }[rule.action] || 1;

    return baseValue * successRate * (1 - riskFactor * 0.5);
  }

  /**
   * 选择目标（传球目标、防守目标等）
   */
  selectTarget(rule, visibleEnvironment) {
    if (rule.action === "pass") {
      // 选择最优传球目标
      const openTeammates = visibleEnvironment.teammates.filter(t => t.isOpen);
      if (openTeammates.length === 0) return null;

      return openTeammates.reduce((best, current) => {
        const currentScore = this.calculatePassTargetScore(current);
        const bestScore = this.calculatePassTargetScore(best);
        return currentScore > bestScore ? current : best;
      }).id;
    }

    if (rule.action === "defend" || rule.action === "tackle") {
      // 选择最威胁的对手
      return visibleEnvironment.opponents
        .filter(o => o.threat > 0)
        .sort((a, b) => b.threat - a.threat)[0]?.id;
    }

    if (rule.action === "runToPosition") {
      // 选择要跑位的位置
      return this.selectBestRunningPosition(visibleEnvironment);
    }

    return null;
  }

  /**
   * 生成动作参数
   */
  generateActionParameters(rule, situation) {
    if (rule.action === "pass") {
      return {
        power: this.calculatePassPower(situation),
        curve: this.calculatePassCurve(situation),
        timing: 0 // 立即执行
      };
    }

    if (rule.action === "shoot") {
      return {
        power: this.calculateShootPower(situation),
        curve: this.calculateShootCurve(situation),
        timing: 0
      };
    }

    return {};
  }

  // ========== 辅助函数 ==========

  isInShootingRange(situation) {
    return situation.ballPosition.distanceToGoal < 25;
  }

  hasOpenSpace(situation) {
    return situation.visibleOpponents.filter(o => o.distance < 10).length < 3;
  }

  defensiveGapNearby(situation) {
    // 检查防线是否有漏洞
    return false; // 简化实现
  }

  calculatePassTargetScore(teammate) {
    return teammate.openDegree * 0.6 + (1 - teammate.distance / 50) * 0.4;
  }

  selectBestRunningPosition(environment) {
    // 选择最优跑位位置
    return null;
  }

  calculatePassPower(situation) {
    return Math.min(1, situation.targetDistance / 50);
  }

  calculatePassCurve(situation) {
    return 0; // 简化实现
  }

  calculateShootPower(situation) {
    return 0.8; // 射门尽力
  }

  calculateShootCurve(situation) {
    return 0;
  }

  getDefaultAction(situation) {
    return {
      playerId: this.playerId,
      actionType: "hold",
      target: null,
      parameters: {},
      expectedSuccessRate: 1.0
    };
  }
}

/**
 * 比赛执行引擎
 */
class MatchExecutor {
  constructor(homeTeam, awayTeam, configurations) {
    this.homeTeam = homeTeam; // 11个PlayerAgent
    this.awayTeam = awayTeam;
    this.allPlayers = [...homeTeam, ...awayTeam];
    this.configs = configurations;
    this.gameState = {
      phase: "kickoff",
      ballPosition: { x: 52.5, y: 34, z: 0 },
      ballVelocity: { x: 0, y: 0 },
      ballOwner: null,
      score: { home: 0, away: 0 },
      time: 0
    };
    this.events = [];
  }

  /**
   * 运行一帧比赛
   */
  simulateFrame() {
    // Phase 1: 环境更新
    this.updateEnvironment();

    // Phase 2: 所有球员并行做决策
    const allActions = this.allPlayers.map(player => player.makeDecision(
      this.gameState,
      this.getVisibleEnvironment(player),
      this.getTacticalInfo(player)
    ));

    // Phase 3: 规则验证
    const validatedActions = this.validateActions(allActions);

    // Phase 4: 物理执行
    this.executeActions(validatedActions);

    // Phase 5: 状态更新
    this.updatePlayerStates(validatedActions);

    // Phase 6: 反馈记录
    this.recordEvents(validatedActions);
  }

  updateEnvironment() {
    // 更新球的位置和速度
    // 更新所有球员的可见范围
  }

  getVisibleEnvironment(player) {
    // 根据球员的视野范围，返回他能看到的信息
    return {
      teammates: [],
      opponents: [],
      ballPosition: this.gameState.ballPosition
    };
  }

  getTacticalInfo(player) {
    // 根据队伍和位置，返回战术信息
    return {};
  }

  validateActions(actions) {
    // 规则系统验证所有动作
    return actions.filter(action => {
      // 检查越位、犯规等
      return true; // 简化实现
    });
  }

  executeActions(actions) {
    // 物理系统执行所有合法动作
  }

  updatePlayerStates(actions) {
    // 更新每个球员的疲劳、心理等状态
  }

  recordEvents(actions) {
    // 记录所有事件
  }

  /**
   * 运行完整的比赛模拟
   */
  runFullMatch() {
    const matchDurationFrames = 90 * 60 * 60; // 90分钟 × 60秒 × 60帧

    for (let frame = 0; frame < matchDurationFrames; frame++) {
      this.simulateFrame();
    }

    return this.generateMatchReport();
  }

  generateMatchReport() {
    return {
      finalScore: this.gameState.score,
      events: this.events,
      playerStats: this.allPlayers.map(p => p.state)
    };
  }
}
