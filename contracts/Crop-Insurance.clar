


(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_POLICY (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_POLICY_EXISTS (err u103))
(define-constant ERR_POLICY_NOT_FOUND (err u104))
(define-constant ERR_POLICY_EXPIRED (err u105))
(define-constant ERR_ALREADY_CLAIMED (err u106))
(define-constant ERR_INVALID_ORACLE (err u107))
(define-constant ERR_CLAIM_CONDITIONS_NOT_MET (err u108))

(define-data-var contract-balance uint u0)
(define-data-var next-policy-id uint u1)
(define-data-var oracle-address (optional principal) none)

(define-map policies
  { policy-id: uint }
  {
    farmer: principal,
    crop-type: (string-ascii 50),
    coverage-amount: uint,
    premium-paid: uint,
    start-block: uint,
    end-block: uint,
    location: (string-ascii 100),
    is-active: bool,
    claimed: bool
  }
)

(define-map farmer-policies
  { farmer: principal }
  { policy-ids: (list 10 uint) }
)

(define-map weather-reports
  { location: (string-ascii 100), report-block: uint }
  {
    temperature: int,
    rainfall: uint,
    severity-score: uint,
    reporter: principal
  }
)

(define-map crop-failure-reports
  { policy-id: uint }
  {
    damage-percentage: uint,
    report-block: uint,
    verified: bool,
    reporter: principal
  }
)

(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set oracle-address (some new-oracle))
    (ok true)
  )
)

(define-public (fund-contract)
  (let ((amount (stx-get-balance tx-sender)))
    (begin
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (var-set contract-balance (+ (var-get contract-balance) amount))
      (ok amount)
    )
  )
)

(define-public (purchase-policy (crop-type (string-ascii 50)) (coverage-amount uint) (duration-blocks uint) (location (string-ascii 100)))
  (let (
    (policy-id (var-get next-policy-id))
    (premium (calculate-premium coverage-amount duration-blocks))
    (current-block stacks-block-height)
    (end-block (+ current-block duration-blocks))
  )
    (begin
      (asserts! (> coverage-amount u0) ERR_INVALID_POLICY)
      (asserts! (> duration-blocks u0) ERR_INVALID_POLICY)
      (asserts! (>= (stx-get-balance tx-sender) premium) ERR_INSUFFICIENT_FUNDS)
      
      (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
      
      (map-set policies
        { policy-id: policy-id }
        {
          farmer: tx-sender,
          crop-type: crop-type,
          coverage-amount: coverage-amount,
          premium-paid: premium,
          start-block: current-block,
          end-block: end-block,
          location: location,
          is-active: true,
          claimed: false
        }
      )
      
      (let ((current-policies (default-to { policy-ids: (list) } (map-get? farmer-policies { farmer: tx-sender }))))
        (map-set farmer-policies
          { farmer: tx-sender }
          { policy-ids: (unwrap! (as-max-len? (append (get policy-ids current-policies) policy-id) u10) ERR_INVALID_POLICY) }
        )
      )
      
      (var-set next-policy-id (+ policy-id u1))
      (var-set contract-balance (+ (var-get contract-balance) premium))
      (ok policy-id)
    )
  )
)

(define-public (submit-weather-report (location (string-ascii 100)) (temperature int) (rainfall uint) (severity-score uint))
  (begin
    (asserts! (is-some (var-get oracle-address)) ERR_INVALID_ORACLE)
    (asserts! (is-eq tx-sender (unwrap-panic (var-get oracle-address))) ERR_UNAUTHORIZED)
    
    (map-set weather-reports
      { location: location, report-block: stacks-block-height }
      {
        temperature: temperature,
        rainfall: rainfall,
        severity-score: severity-score,
        reporter: tx-sender
      }
    )
    (ok true)
  )
)

(define-public (submit-crop-failure-report (policy-id uint) (damage-percentage uint))
  (let ((policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND)))
    (begin
      (asserts! (is-some (var-get oracle-address)) ERR_INVALID_ORACLE)
      (asserts! (is-eq tx-sender (unwrap-panic (var-get oracle-address))) ERR_UNAUTHORIZED)
      (asserts! (get is-active policy-data) ERR_INVALID_POLICY)
      (asserts! (<= damage-percentage u100) ERR_INVALID_POLICY)
      
      (map-set crop-failure-reports
        { policy-id: policy-id }
        {
          damage-percentage: damage-percentage,
          report-block: stacks-block-height,
          verified: true,
          reporter: tx-sender
        }
      )
      (ok true)
    )
  )
)

(define-public (claim-payout (policy-id uint))
  (let (
    (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
    (failure-report (map-get? crop-failure-reports { policy-id: policy-id }))
    (weather-report (map-get? weather-reports { location: (get location policy-data), report-block: stacks-block-height }))
  )
    (begin
      (asserts! (is-eq tx-sender (get farmer policy-data)) ERR_UNAUTHORIZED)
      (asserts! (get is-active policy-data) ERR_INVALID_POLICY)
      (asserts! (not (get claimed policy-data)) ERR_ALREADY_CLAIMED)
      (asserts! (<= stacks-block-height (get end-block policy-data)) ERR_POLICY_EXPIRED)
      
      (let ((payout-amount (calculate-payout policy-id policy-data failure-report weather-report)))
        (begin
          (asserts! (> payout-amount u0) ERR_CLAIM_CONDITIONS_NOT_MET)
          (asserts! (>= (var-get contract-balance) payout-amount) ERR_INSUFFICIENT_FUNDS)
          
          (try! (as-contract (stx-transfer? payout-amount tx-sender (get farmer policy-data))))
          
          (map-set policies
            { policy-id: policy-id }
            (merge policy-data { claimed: true, is-active: false })
          )
          
          (var-set contract-balance (- (var-get contract-balance) payout-amount))
          (ok payout-amount)
        )
      )
    )
  )
)

(define-public (cancel-policy (policy-id uint))
  (let ((policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND)))
    (begin
      (asserts! (is-eq tx-sender (get farmer policy-data)) ERR_UNAUTHORIZED)
      (asserts! (get is-active policy-data) ERR_INVALID_POLICY)
      (asserts! (not (get claimed policy-data)) ERR_ALREADY_CLAIMED)
      
      (map-set policies
        { policy-id: policy-id }
        (merge policy-data { is-active: false })
      )
      (ok true)
    )
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-farmer-policies (farmer principal))
  (map-get? farmer-policies { farmer: farmer })
)

(define-read-only (get-weather-report (location (string-ascii 100)) (report-block uint))
  (map-get? weather-reports { location: location, report-block: report-block })
)

(define-read-only (get-crop-failure-report (policy-id uint))
  (map-get? crop-failure-reports { policy-id: policy-id })
)

(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

(define-read-only (get-oracle-address)
  (var-get oracle-address)
)

(define-private (calculate-premium (coverage-amount uint) (duration-blocks uint))
  (let ((base-rate u5))
    (/ (* coverage-amount base-rate duration-blocks) u100000)
  )
)

(define-private (calculate-payout (policy-id uint) (policy-data (tuple (farmer principal) (crop-type (string-ascii 50)) (coverage-amount uint) (premium-paid uint) (start-block uint) (end-block uint) (location (string-ascii 100)) (is-active bool) (claimed bool))) (failure-report (optional (tuple (damage-percentage uint) (report-block uint) (verified bool) (reporter principal)))) (weather-report (optional (tuple (temperature int) (rainfall uint) (severity-score uint) (reporter principal)))))
  (let (
    (coverage (get coverage-amount policy-data))
    (damage-pct (match failure-report some-report (get damage-percentage some-report) u0))
    (weather-severity (match weather-report some-weather (get severity-score some-weather) u0))
  )
    (if (or (>= damage-pct u50) (>= weather-severity u70))
      (if (>= damage-pct u80)
        coverage
        (/ (* coverage damage-pct) u100)
      )
      u0
    )
  )
)

(define-read-only (estimate-premium (coverage-amount uint) (duration-blocks uint))
  (calculate-premium coverage-amount duration-blocks)
)

(define-read-only (estimate-payout (policy-id uint))
  (let (
    (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) u0))
    (failure-report (map-get? crop-failure-reports { policy-id: policy-id }))
    (weather-report (map-get? weather-reports { location: (get location policy-data), report-block: stacks-block-height }))
  )
    (calculate-payout policy-id policy-data failure-report weather-report)
  )
)
