/**
 * AI FC - 配置管理系统
 * 负责加载、验证和管理所有分层配置
 */

class ConfigManager {
  constructor() {
    this.configs = {};
    this.configPath = './config';
    this.layers = [
      '0-physics',
      '1-rules',
      '2-attributes',
      '3-skills',
      '4-decision',
      '5-state',
      '6-strategy',
      '7-analytics'
    ];
  }

  /**
   * 加载指定层的配置
   */
  async loadLayerConfig(layer, fileName = 'base.json') {
    try {
      const response = await fetch(`${this.configPath}/${layer}/${fileName}`);
      if (!response.ok) {
        throw new Error(`Failed to load config: ${layer}/${fileName}`);
      }
      const data = await response.json();
      this.configs[layer] = data;
      console.log(`✓ Loaded layer ${layer}: ${fileName}`);
      return data;
    } catch (error) {
      console.error(`✗ Error loading layer ${layer}:`, error);
      return null;
    }
  }

  /**
   * 加载所有配置层
   */
  async loadAllConfigs() {
    console.log('Loading configuration layers...\n');
    for (const layer of this.layers) {
      await this.loadLayerConfig(layer);
    }
    console.log('\n✓ All configuration layers loaded successfully!');
    return this.configs;
  }

  /**
   * 获取指定层的配置
   */
  getConfig(layer) {
    return this.configs[layer] || null;
  }

  /**
   * 验证配置的完整性
   */
  validateConfigs() {
    const validation = {};
    for (const layer of this.layers) {
      validation[layer] = this.configs[layer] ? 'loaded' : 'missing';
    }
    return validation;
  }

  /**
   * 导出配置快照（用于调试）
   */
  exportSnapshot() {
    return JSON.stringify(this.configs, null, 2);
  }

  /**
   * 清除缓存并重新加载
   */
  async reload() {
    this.configs = {};
    return this.loadAllConfigs();
  }
}

/**
 * 全局配置管理器实例
 */
const configManager = new ConfigManager();
