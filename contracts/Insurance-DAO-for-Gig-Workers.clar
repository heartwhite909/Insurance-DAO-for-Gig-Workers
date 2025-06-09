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

(define-data-var total-pool uint u0)
(define-data-var member-count uint u0)
(define-data-var claim-counter uint u0)
(define-data-var min-contribution uint u1000000)

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
