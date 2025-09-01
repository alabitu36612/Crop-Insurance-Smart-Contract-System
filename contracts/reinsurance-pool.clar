(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_NOT_MEMBER (err u200))
(define-constant ERR_ALREADY_MEMBER (err u201))
(define-constant ERR_INVALID_AMOUNT (err u202))
(define-constant ERR_POOL_LIMIT_REACHED (err u203))

(define-constant MAX_POOL_MEMBERS u50)
(define-constant MIN_CONTRIBUTION u100000)
(define-constant DISCOUNT_RATE u15)
(define-constant BOOST_RATE u25)

(define-data-var pool-balance uint u0)
(define-data-var member-count uint u0)
(define-data-var total-contributions uint u0)

(define-map pool-members
  { member: principal }
  {
    contribution-amount: uint,
    joined-at: uint,
    is-active: bool,
    claims-boosted: uint
  }
)

(define-map member-list
  { index: uint }
  { member: principal }
)

(define-public (join-pool (contribution-amount uint))
  (begin
    (asserts! (>= contribution-amount MIN_CONTRIBUTION) ERR_INVALID_AMOUNT)
    (asserts! (< (var-get member-count) MAX_POOL_MEMBERS) ERR_POOL_LIMIT_REACHED)
    (asserts! (is-none (map-get? pool-members { member: tx-sender })) ERR_ALREADY_MEMBER)
    (asserts! (>= (stx-get-balance tx-sender) contribution-amount) ERR_INSUFFICIENT_FUNDS)
    
    (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
    
    (map-set pool-members
      { member: tx-sender }
      {
        contribution-amount: contribution-amount,
        joined-at: stacks-block-height,
        is-active: true,
        claims-boosted: u0
      }
    )
    
    (map-set member-list
      { index: (var-get member-count) }
      { member: tx-sender }
    )
    
    (var-set member-count (+ (var-get member-count) u1))
    (var-set pool-balance (+ (var-get pool-balance) contribution-amount))
    (var-set total-contributions (+ (var-get total-contributions) contribution-amount))
    (ok true)
  )
)

(define-public (leave-pool)
  (let ((member-data (unwrap! (map-get? pool-members { member: tx-sender }) ERR_NOT_MEMBER)))
    (begin
      (asserts! (get is-active member-data) ERR_NOT_MEMBER)
      
      (let ((refund-amount (/ (get contribution-amount member-data) u2)))
        (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
        
        (map-set pool-members
          { member: tx-sender }
          (merge member-data { is-active: false })
        )
        
        (var-set pool-balance (- (var-get pool-balance) refund-amount))
        (ok refund-amount)
      )
    )
  )
)

(define-read-only (get-premium-discount (farmer principal) (base-premium uint))
  (match (map-get? pool-members { member: farmer })
    some-member (if (get is-active some-member) (/ (* base-premium DISCOUNT_RATE) u100) u0)
    u0
  )
)

(define-read-only (get-claim-boost (farmer principal) (base-payout uint))
  (match (map-get? pool-members { member: farmer })
    some-member (if (get is-active some-member) (/ (* base-payout BOOST_RATE) u100) u0)
    u0
  )
)

(define-read-only (get-member-info (member principal))
  (map-get? pool-members { member: member })
)

(define-read-only (get-pool-stats)
  {
    balance: (var-get pool-balance),
    member-count: (var-get member-count),
    total-contributions: (var-get total-contributions)
  }
)
