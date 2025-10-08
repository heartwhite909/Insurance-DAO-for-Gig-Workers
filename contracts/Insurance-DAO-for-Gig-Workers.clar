(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_ALREADY_MEMBER (err u103))
(define-constant ERR_NOT_MEMBER (err u104))
(define-constant ERR_CLAIM_EXISTS (err u105))
(define-constant ERR_CLAIM_NOT_FOUND (err u106))
(define-constant ERR_VOTING_ENDED (err u107))
(define-constant ERR_ALREADY_VOTED (err u108))
(define-constant ERR_CLAIM_NOT_APPROVED (err u109))
(define-constant ERR_CLAIM_ALREADY_PAID (err u110))
(define-constant ERR_STREAK_NOT_FOUND (err u200))
(define-constant ERR_STREAK_ALREADY_EXISTS (err u201))
(define-constant STREAK_BONUS_THRESHOLD u3)
(define-constant STREAK_BONUS_MULTIPLIER u2)
(define-constant CONTRIBUTION_WINDOW u1008)

(define-constant REPUTATION_GOOD_VOTE u10)
(define-constant REPUTATION_BAD_VOTE u5)
(define-constant REPUTATION_DECAY_RATE u2)
(define-constant REPUTATION_DECAY_BLOCKS u4320)
(define-constant MAX_REPUTATION u1000)
(define-constant MIN_REPUTATION u0)

(define-constant EMERGENCY_RESERVE_PERCENTAGE u10)
(define-constant EMERGENCY_THRESHOLD_PERCENTAGE u20)
(define-constant ERR_EMERGENCY_NOT_TRIGGERED (err u300))
(define-constant ERR_INSUFFICIENT_RESERVE (err u301))

(define-constant REFERRAL_REWARD_PERCENTAGE u5)
(define-constant MAX_REFERRAL_DEPTH u3)
(define-constant ERR_INVALID_REFERRER (err u400))
(define-constant ERR_SELF_REFERRAL (err u401))

(define-data-var total-referral-rewards uint u0)

(define-data-var emergency-reserve uint u0)
(define-data-var reserve-activated bool false)
(define-data-var emergency-withdrawals uint u0)


(define-data-var total-pool uint u0)
(define-data-var member-count uint u0)
(define-data-var claim-counter uint u0)
(define-data-var min-contribution uint u1000000)
(define-data-var total-active-streaks uint u0)
(define-data-var highest-streak uint u0)

(define-map members
  principal
  {
    total-contributed: uint,
    join-block: uint,
    active: bool
  }
)

(define-map claims
  uint
  {
    claimant: principal,
    amount: uint,
    description: (string-ascii 256),
    created-block: uint,
    voting-end-block: uint,
    votes-for: uint,
    votes-against: uint,
    approved: bool,
    paid: bool
  }
)

(define-map claim-votes
  { claim-id: uint, voter: principal }
  { vote: bool }
)

(define-public (join-dao (contribution uint))
  (let
    (
      (sender tx-sender)
      (current-member (map-get? members sender))
    )
    (asserts! (>= contribution (var-get min-contribution)) ERR_INVALID_AMOUNT)
    (asserts! (is-none current-member) ERR_ALREADY_MEMBER)
    (try! (stx-transfer? contribution sender (as-contract tx-sender)))
    (map-set members sender {
      total-contributed: contribution,
      join-block: stacks-block-height,
      active: true
    })
    (var-set total-pool (+ (var-get total-pool) contribution))
    (var-set member-count (+ (var-get member-count) u1))
    (ok true)
  )
)

(define-public (contribute (amount uint))
  (let
    (
      (sender tx-sender)
      (member-data (unwrap! (map-get? members sender) ERR_NOT_MEMBER))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get active member-data) ERR_NOT_MEMBER)
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    (map-set members sender (merge member-data {
      total-contributed: (+ (get total-contributed member-data) amount)
    }))
    (var-set total-pool (+ (var-get total-pool) amount))
    (ok true)
  )
)

(define-public (submit-claim (amount uint) (description (string-ascii 256)))
  (let
    (
      (sender tx-sender)
      (member-data (unwrap! (map-get? members sender) ERR_NOT_MEMBER))
      (claim-id (+ (var-get claim-counter) u1))
      (voting-period u144)
    )
    (asserts! (get active member-data) ERR_NOT_MEMBER)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (/ (var-get total-pool) u4)) ERR_INVALID_AMOUNT)
    (map-set claims claim-id {
      claimant: sender,
      amount: amount,
      description: description,
      created-block: stacks-block-height,
      voting-end-block: (+ stacks-block-height voting-period),
      votes-for: u0,
      votes-against: u0,
      approved: false,
      paid: false
    })
    (var-set claim-counter claim-id)
    (ok claim-id)
  )
)

(define-public (vote-on-claim (claim-id uint) (vote bool))
  (let
    (
      (sender tx-sender)
      (member-data (unwrap! (map-get? members sender) ERR_NOT_MEMBER))
      (claim-data (unwrap! (map-get? claims claim-id) ERR_CLAIM_NOT_FOUND))
      (vote-key { claim-id: claim-id, voter: sender })
      (existing-vote (map-get? claim-votes vote-key))
      (voting-power (calculate-voting-power (get total-contributed member-data)))
    )
    (asserts! (get active member-data) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get voting-end-block claim-data)) ERR_VOTING_ENDED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (map-set claim-votes vote-key { vote: vote })
    (if vote
      (map-set claims claim-id (merge claim-data {
        votes-for: (+ (get votes-for claim-data) voting-power)
      }))
      (map-set claims claim-id (merge claim-data {
        votes-against: (+ (get votes-against claim-data) voting-power)
      }))
    )
    (ok true)
  )
)

(define-public (finalize-claim (claim-id uint))
  (let
    (
      (claim-data (unwrap! (map-get? claims claim-id) ERR_CLAIM_NOT_FOUND))
      (total-votes (+ (get votes-for claim-data) (get votes-against claim-data)))
      (approval-threshold (/ (* (var-get member-count) u60) u100))
    )
    (asserts! (>= stacks-block-height (get voting-end-block claim-data)) ERR_VOTING_ENDED)
    (asserts! (not (get approved claim-data)) ERR_CLAIM_EXISTS)
    (if (and 
          (> (get votes-for claim-data) (get votes-against claim-data))
          (>= (get votes-for claim-data) approval-threshold))
      (begin
        (map-set claims claim-id (merge claim-data { approved: true }))
        (ok true)
      )
      (ok false)
    )
  )
)

(define-public (payout-claim (claim-id uint))
  (let
    (
      (claim-data (unwrap! (map-get? claims claim-id) ERR_CLAIM_NOT_FOUND))
      (claimant (get claimant claim-data))
      (amount (get amount claim-data))
    )
    (asserts! (get approved claim-data) ERR_CLAIM_NOT_APPROVED)
    (asserts! (not (get paid claim-data)) ERR_CLAIM_ALREADY_PAID)
    (asserts! (>= (var-get total-pool) amount) ERR_INSUFFICIENT_FUNDS)
    (try! (as-contract (stx-transfer? amount tx-sender claimant)))
    (map-set claims claim-id (merge claim-data { paid: true }))
    (var-set total-pool (- (var-get total-pool) amount))
    (ok true)
  )
)

(define-public (leave-dao)
  (let
    (
      (sender tx-sender)
      (member-data (unwrap! (map-get? members sender) ERR_NOT_MEMBER))
    )
    (asserts! (get active member-data) ERR_NOT_MEMBER)
    (map-set members sender (merge member-data { active: false }))
    (var-set member-count (- (var-get member-count) u1))
    (ok true)
  )
)

(define-public (update-min-contribution (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set min-contribution new-amount)
    (ok true)
  )
)

(define-read-only (get-member-info (member principal))
  (map-get? members member)
)

(define-read-only (get-claim-info (claim-id uint))
  (map-get? claims claim-id)
)

(define-read-only (get-pool-stats)
  {
    total-pool: (var-get total-pool),
    member-count: (var-get member-count),
    claim-counter: (var-get claim-counter),
    min-contribution: (var-get min-contribution)
  }
)

(define-read-only (get-vote (claim-id uint) (voter principal))
  (map-get? claim-votes { claim-id: claim-id, voter: voter })
)

(define-read-only (calculate-voting-power (contribution uint))
  (if (< contribution u5000000)
    u1
    (if (< contribution u10000000)
      u2
      u3
    )
  )
)

(define-read-only (is-member (address principal))
  (match (map-get? members address)
    member-data (get active member-data)
    false
  )
)

(define-read-only (get-member-voting-power (member principal))
  (match (map-get? members member)
    member-data (calculate-voting-power (get total-contributed member-data))
    u0
  )
)

(define-map contribution-streaks
  principal
  {
    current-streak: uint,
    longest-streak: uint,
    last-contribution-block: uint,
    streak-start-block: uint,
    bonus-voting-power: uint
  }
)

(define-map streak-leaderboard
  uint
  { member: principal, streak: uint }
)

(define-public (initialize-streak (member principal))
  (let
    (
      (existing-streak (map-get? contribution-streaks member))
      (current-block stacks-block-height)
    )
    (asserts! (is-none existing-streak) ERR_STREAK_ALREADY_EXISTS)
    (map-set contribution-streaks member {
      current-streak: u1,
      longest-streak: u1,
      last-contribution-block: current-block,
      streak-start-block: current-block,
      bonus-voting-power: u0
    })
    (var-set total-active-streaks (+ (var-get total-active-streaks) u1))
    (ok true)
  )
)

(define-public (update-streak (member principal))
  (let
    (
      (streak-data (unwrap! (map-get? contribution-streaks member) ERR_STREAK_NOT_FOUND))
      (current-block stacks-block-height)
      (blocks-since-last (- current-block (get last-contribution-block streak-data)))
      (new-streak (if (<= blocks-since-last CONTRIBUTION_WINDOW)
                    (+ (get current-streak streak-data) u1)
                    u1))
      (new-longest (if (> new-streak (get longest-streak streak-data))
                     new-streak
                     (get longest-streak streak-data)))
      (bonus-power (if (>= new-streak STREAK_BONUS_THRESHOLD)
                     (* (/ new-streak STREAK_BONUS_THRESHOLD) STREAK_BONUS_MULTIPLIER)
                     u0))
    )
    (map-set contribution-streaks member {
      current-streak: new-streak,
      longest-streak: new-longest,
      last-contribution-block: current-block,
      streak-start-block: (if (is-eq new-streak u1) current-block (get streak-start-block streak-data)),
      bonus-voting-power: bonus-power
    })
    (if (> new-streak (var-get highest-streak))
      (var-set highest-streak new-streak)
      true
    )
    (ok new-streak)
  )
)

(define-read-only (get-streak-info (member principal))
  (map-get? contribution-streaks member)
)

(define-read-only (get-streak-bonus (member principal))
  (match (map-get? contribution-streaks member)
    streak-data (get bonus-voting-power streak-data)
    u0
  )
)

(define-read-only (get-enhanced-voting-power (member principal) (base-power uint))
  (let
    (
      (streak-bonus (get-streak-bonus member))
    )
    (+ base-power streak-bonus)
  )
)

(define-read-only (get-streak-stats)
  {
    total-active-streaks: (var-get total-active-streaks),
    highest-streak: (var-get highest-streak)
  }
)

(define-read-only (is-streak-active (member principal))
  (match (map-get? contribution-streaks member)
    streak-data (let
      (
        (blocks-since-last (- stacks-block-height (get last-contribution-block streak-data)))
      )
      (<= blocks-since-last CONTRIBUTION_WINDOW)
    )
    false
  )
)

(define-map member-reputation
  principal
  {
    current-score: uint,
    total-votes: uint,
    correct-votes: uint,
    last-decay-block: uint,
    reputation-tier: uint
  }
)

(define-public (initialize-reputation (member principal))
  (let
    (
      (existing-rep (map-get? member-reputation member))
    )
    (if (is-none existing-rep)
      (begin
        (map-set member-reputation member {
          current-score: u100,
          total-votes: u0,
          correct-votes: u0,
          last-decay-block: stacks-block-height,
          reputation-tier: u1
        })
        (ok true)
      )
      (ok false)
    )
  )
)

(define-public (update-vote-reputation (voter principal) (claim-id uint) (was-correct bool))
  (let
    (
      (rep-data (unwrap! (map-get? member-reputation voter) (err u404)))
      (score-change (if was-correct REPUTATION_GOOD_VOTE (- u0 REPUTATION_BAD_VOTE)))
      (new-score (+ (get current-score rep-data) score-change))
      (capped-score (if (> new-score MAX_REPUTATION) MAX_REPUTATION 
                      (if (< new-score MIN_REPUTATION) MIN_REPUTATION new-score)))
      (new-tier (calculate-reputation-tier capped-score))
    )
    (map-set member-reputation voter {
      current-score: capped-score,
      total-votes: (+ (get total-votes rep-data) u1),
      correct-votes: (if was-correct (+ (get correct-votes rep-data) u1) (get correct-votes rep-data)),
      last-decay-block: (get last-decay-block rep-data),
      reputation-tier: new-tier
    })
    (ok capped-score)
  )
)

(define-public (apply-reputation-decay (member principal))
  (let
    (
      (rep-data (unwrap! (map-get? member-reputation member) (err u404)))
      (blocks-passed (- stacks-block-height (get last-decay-block rep-data)))
      (decay-periods (/ blocks-passed REPUTATION_DECAY_BLOCKS))
    )
    (if (> decay-periods u0)
      (let
        (
          (decay-amount (* decay-periods REPUTATION_DECAY_RATE))
          (new-score (if (> (get current-score rep-data) decay-amount)
                       (- (get current-score rep-data) decay-amount)
                       MIN_REPUTATION))
          (new-tier (calculate-reputation-tier new-score))
        )
        (map-set member-reputation member (merge rep-data {
          current-score: new-score,
          last-decay-block: stacks-block-height,
          reputation-tier: new-tier
        }))
        (ok new-score)
      )
      (ok (get current-score rep-data))
    )
  )
)

(define-read-only (calculate-reputation-tier (score uint))
  (if (>= score u800) u5
    (if (>= score u600) u4
      (if (>= score u400) u3
        (if (>= score u200) u2 u1)))))

(define-read-only (get-reputation-info (member principal))
  (map-get? member-reputation member))

(define-read-only (get-reputation-multiplier (member principal))
  (match (map-get? member-reputation member)
    rep-data (get reputation-tier rep-data)
    u1))


(define-map emergency-access-log
  uint
  {
    timestamp: uint,
    amount: uint,
    main-pool-balance: uint,
    authorized-by: principal
  }
)

(define-public (fund-emergency-reserve (contribution-amount uint))
  (let
    (
      (reserve-contribution (/ (* contribution-amount EMERGENCY_RESERVE_PERCENTAGE) u100))
    )
    (var-set emergency-reserve (+ (var-get emergency-reserve) reserve-contribution))
    (ok reserve-contribution)
  )
)

(define-public (trigger-emergency-access)
  (let
    (
      (current-pool (var-get total-pool))
      (total-contributions (* (var-get member-count) (var-get min-contribution)))
      (emergency-threshold (/ (* total-contributions EMERGENCY_THRESHOLD_PERCENTAGE) u100))
    )
    (asserts! (<= current-pool emergency-threshold) ERR_EMERGENCY_NOT_TRIGGERED)
    (var-set reserve-activated true)
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (let
    (
      (withdrawal-id (+ (var-get emergency-withdrawals) u1))
    )
    (asserts! (var-get reserve-activated) ERR_EMERGENCY_NOT_TRIGGERED)
    (asserts! (>= (var-get emergency-reserve) amount) ERR_INSUFFICIENT_RESERVE)
    (var-set emergency-reserve (- (var-get emergency-reserve) amount))
    (var-set total-pool (+ (var-get total-pool) amount))
    (var-set emergency-withdrawals withdrawal-id)
    (map-set emergency-access-log withdrawal-id {
      timestamp: stacks-block-height,
      amount: amount,
      main-pool-balance: (var-get total-pool),
      authorized-by: tx-sender
    })
    (ok amount)
  )
)

(define-public (deactivate-emergency-access)
  (let
    (
      (current-pool (var-get total-pool))
      (safe-threshold (/ (* (var-get member-count) (var-get min-contribution) u50) u100))
    )
    (asserts! (>= current-pool safe-threshold) ERR_EMERGENCY_NOT_TRIGGERED)
    (var-set reserve-activated false)
    (ok true)
  )
)

(define-read-only (get-emergency-status)
  {
    reserve-balance: (var-get emergency-reserve),
    is-activated: (var-get reserve-activated),
    total-emergency-withdrawals: (var-get emergency-withdrawals),
    emergency-threshold: (/ (* (* (var-get member-count) (var-get min-contribution)) EMERGENCY_THRESHOLD_PERCENTAGE) u100)
  }
)

(define-read-only (get-emergency-withdrawal-log (withdrawal-id uint))
  (map-get? emergency-access-log withdrawal-id)
)

(define-read-only (calculate-reserve-health)
  (let
    (
      (reserve-balance (var-get emergency-reserve))
      (recommended-reserve (/ (* (var-get total-pool) u15) u100))
    )
    (if (>= reserve-balance recommended-reserve) u100
      (/ (* reserve-balance u100) recommended-reserve))
  )
)

(define-map member-referrals
  principal
  {
    referrer: (optional principal),
    total-referred: uint,
    referral-earnings: uint,
    referral-bonus-power: uint
  }
)

(define-public (join-dao-with-referral (contribution uint) (referrer (optional principal)))
  (let
    (
      (sender tx-sender)
      (current-member (map-get? members sender))
    )
    (asserts! (>= contribution (var-get min-contribution)) ERR_INVALID_AMOUNT)
    (asserts! (is-none current-member) ERR_ALREADY_MEMBER)
    (match referrer
      ref-principal 
        (begin
          (asserts! (not (is-eq sender ref-principal)) ERR_SELF_REFERRAL)
          (asserts! (is-some (map-get? members ref-principal)) ERR_INVALID_REFERRER)
          (unwrap-panic (process-referral-reward ref-principal contribution))
        )
      u0
    )
      (try! (stx-transfer? contribution sender (as-contract tx-sender)))
    (map-set members sender {
      total-contributed: contribution,
      join-block: stacks-block-height,
      active: true
    })
    (map-set member-referrals sender {
      referrer: referrer,
      total-referred: u0,
      referral-earnings: u0,
      referral-bonus-power: u0
    })
    (var-set total-pool (+ (var-get total-pool) contribution))
    (var-set member-count (+ (var-get member-count) u1))
    (ok true)
  )
)

(define-private (process-referral-reward (referrer-address principal) (contribution uint))
  (let
    (
      (reward-amount (/ (* contribution REFERRAL_REWARD_PERCENTAGE) u100))
      (referrer-data (unwrap! (map-get? member-referrals referrer-address) ERR_INVALID_REFERRER))
      (new-bonus-power (/ (+ (get total-referred referrer-data) u1) u3))
    )
    (try! (as-contract (stx-transfer? reward-amount tx-sender referrer-address)))
    (map-set member-referrals referrer-address {
      referrer: (get referrer referrer-data),
      total-referred: (+ (get total-referred referrer-data) u1),
      referral-earnings: (+ (get referral-earnings referrer-data) reward-amount),
      referral-bonus-power: new-bonus-power
    })
    (var-set total-referral-rewards (+ (var-get total-referral-rewards) reward-amount))
    (ok reward-amount)
  )
)

(define-read-only (get-referral-info (member principal))
  (map-get? member-referrals member)
)

(define-read-only (get-referral-stats)
  {
    total-rewards-distributed: (var-get total-referral-rewards)
  }
)