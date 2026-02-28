class_name GameConstants
## 游戏全局常量 - 集中管理共享魔数

# === 攻击阶段节拍配置 ===
const COUNTDOWN_BEATS: int = 4        ## 准备倒计时拍数（第 1 小节）
const INPUT_BEATS: int = 16           ## 攻击输入拍数（第 2-5 小节）
const EXIT_BEATS: int = 4             ## 退出倒计时拍数（第 6 小节）
const TOTAL_ATTACK_BEATS: int = 24    ## 攻击阶段总拍数
const DRUM_START_BEAT: int = 32       ## drum 第 9 小节起拍编号

# === 攻击阶段时间比率 ===
const FIRST_BEAT_DELAY_RATIO: float = 0.5    ## 第一输入拍提前半拍
const AUTO_ENHANCE_DELAY_RATIO: float = 0.5  ## 每拍后半拍自动强化

# === 音乐恢复 ===
const MUSIC_RESUME_LEAD_TIME: float = 0.5    ## 提前淡入秒数

# === 判定时间窗口（秒） ===
const PERFECT_WINDOW: float = 0.050   ## 50 ms
const GREAT_WINDOW: float = 0.100     ## 100 ms
const GOOD_WINDOW: float = 0.150      ## 150 ms

# === MISS 判定 ===
const MISS_THRESHOLD: float = 0.200   ## 超过判定线后 200 ms 算 MISS
