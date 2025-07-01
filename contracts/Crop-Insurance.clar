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
(define-constant MIN_VALIDATORS u2)
(define-constant MAX_VALIDATORS u5)
(define-data-var base-premium-rate uint u5)
(define-data-var max-risk-multiplier uint u300)
(define-data-var min-risk-multiplier uint u50)


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



(define-data-var validator-count uint u0)
(define-data-var high-value-threshold uint u1000000)

(define-map validators
  { validator: principal }
  { is-active: bool, added-at: uint }
)

(define-map policy-approvals
  { policy-id: uint }
  { 
    required-approvals: uint,
    current-approvals: uint,
    approved-by: (list 5 principal),
    is-approved: bool
  }
)

(define-map claim-approvals
  { policy-id: uint }
  {
    required-approvals: uint,
    current-approvals: uint,
    approved-by: (list 5 principal),
    is-approved: bool
  }
)

(define-public (add-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (< (var-get validator-count) MAX_VALIDATORS) ERR_INVALID_POLICY)
    (asserts! (is-none (map-get? validators { validator: validator })) ERR_POLICY_EXISTS)
    
    (map-set validators
      { validator: validator }
      { is-active: true, added-at: stacks-block-height }
    )
    (var-set validator-count (+ (var-get validator-count) u1))
    (ok true)
  )
)

(define-public (remove-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? validators { validator: validator })) ERR_POLICY_NOT_FOUND)
    (asserts! (> (var-get validator-count) MIN_VALIDATORS) ERR_INVALID_POLICY)
    
    (map-delete validators { validator: validator })
    (var-set validator-count (- (var-get validator-count) u1))
    (ok true)
  )
)

(define-public (approve-high-value-policy (policy-id uint))
  (let (
    (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
    (validator-data (unwrap! (map-get? validators { validator: tx-sender }) ERR_UNAUTHORIZED))
    (approval-data (default-to 
      { required-approvals: u2, current-approvals: u0, approved-by: (list), is-approved: false }
      (map-get? policy-approvals { policy-id: policy-id })
    ))
  )
    (begin
      (asserts! (get is-active validator-data) ERR_UNAUTHORIZED)
      (asserts! (>= (get coverage-amount policy-data) (var-get high-value-threshold)) ERR_INVALID_POLICY)
      (asserts! (is-none (index-of (get approved-by approval-data) tx-sender)) ERR_POLICY_EXISTS)
      
      (let (
        (new-approvals (+ (get current-approvals approval-data) u1))
        (new-approved-by (unwrap! (as-max-len? (append (get approved-by approval-data) tx-sender) u5) ERR_INVALID_POLICY))
        (is-fully-approved (>= new-approvals (get required-approvals approval-data)))
      )
        (map-set policy-approvals
          { policy-id: policy-id }
          {
            required-approvals: (get required-approvals approval-data),
            current-approvals: new-approvals,
            approved-by: new-approved-by,
            is-approved: is-fully-approved
          }
        )
        (ok is-fully-approved)
      )
    )
  )
)

(define-public (approve-high-value-claim (policy-id uint))
  (let (
    (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
    (validator-data (unwrap! (map-get? validators { validator: tx-sender }) ERR_UNAUTHORIZED))
    (approval-data (default-to 
      { required-approvals: u2, current-approvals: u0, approved-by: (list), is-approved: false }
      (map-get? claim-approvals { policy-id: policy-id })
    ))
  )
    (begin
      (asserts! (get is-active validator-data) ERR_UNAUTHORIZED)
      (asserts! (>= (get coverage-amount policy-data) (var-get high-value-threshold)) ERR_INVALID_POLICY)
      (asserts! (is-none (index-of (get approved-by approval-data) tx-sender)) ERR_POLICY_EXISTS)
      
      (let (
        (new-approvals (+ (get current-approvals approval-data) u1))
        (new-approved-by (unwrap! (as-max-len? (append (get approved-by approval-data) tx-sender) u5) ERR_INVALID_POLICY))
        (is-fully-approved (>= new-approvals (get required-approvals approval-data)))
      )
        (map-set claim-approvals
          { policy-id: policy-id }
          {
            required-approvals: (get required-approvals approval-data),
            current-approvals: new-approvals,
            approved-by: new-approved-by,
            is-approved: is-fully-approved
          }
        )
        (ok is-fully-approved)
      )
    )
  )
)

(define-public (set-high-value-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set high-value-threshold new-threshold)
    (ok true)
  )
)

(define-read-only (get-policy-approval-status (policy-id uint))
  (map-get? policy-approvals { policy-id: policy-id })
)

(define-read-only (get-claim-approval-status (policy-id uint))
  (map-get? claim-approvals { policy-id: policy-id })
)

(define-read-only (is-validator (validator principal))
  (match (map-get? validators { validator: validator })
    some-data (get is-active some-data)
    false
  )
)

(define-private (requires-approval (coverage-amount uint))
  (>= coverage-amount (var-get high-value-threshold))
)


(define-map location-risk-profiles
  { location: (string-ascii 100) }
  {
    total-policies: uint,
    total-claims: uint,
    total-payouts: uint,
    avg-weather-severity: uint,
    risk-score: uint,
    last-updated: uint
  }
)

(define-map crop-risk-profiles
  { crop-type: (string-ascii 50) }
  {
    total-policies: uint,
    total-claims: uint,
    success-rate: uint,
    risk-multiplier: uint,
    last-updated: uint
  }
)

(define-map seasonal-adjustments
  { season: uint }
  { adjustment-factor: uint, active: bool }
)

(define-public (update-location-risk (location (string-ascii 100)) (weather-severity uint))
  (let (
    (current-profile (default-to 
      { total-policies: u0, total-claims: u0, total-payouts: u0, avg-weather-severity: u0, risk-score: u50, last-updated: u0 }
      (map-get? location-risk-profiles { location: location })
    ))
  )
    (begin
      (asserts! (is-some (var-get oracle-address)) ERR_INVALID_ORACLE)
      (asserts! (is-eq tx-sender (unwrap-panic (var-get oracle-address))) ERR_UNAUTHORIZED)
      
      (let (
        (new-avg-severity (/ (+ (* (get avg-weather-severity current-profile) (get total-policies current-profile)) weather-severity) (+ (get total-policies current-profile) u1)))
        (new-risk-score (calculate-location-risk-score new-avg-severity (get total-claims current-profile) (get total-policies current-profile)))
      )
        (map-set location-risk-profiles
          { location: location }
          {
            total-policies: (get total-policies current-profile),
            total-claims: (get total-claims current-profile),
            total-payouts: (get total-payouts current-profile),
            avg-weather-severity: new-avg-severity,
            risk-score: new-risk-score,
            last-updated: stacks-block-height
          }
        )
        (ok new-risk-score)
      )
    )
  )
)

(define-public (update-crop-risk (crop-type (string-ascii 50)) (success-rate uint))
  (let (
    (current-profile (default-to 
      { total-policies: u0, total-claims: u0, success-rate: u100, risk-multiplier: u100, last-updated: u0 }
      (map-get? crop-risk-profiles { crop-type: crop-type })
    ))
  )
    (begin
      (asserts! (is-some (var-get oracle-address)) ERR_INVALID_ORACLE)
      (asserts! (is-eq tx-sender (unwrap-panic (var-get oracle-address))) ERR_UNAUTHORIZED)
      (asserts! (<= success-rate u100) ERR_INVALID_POLICY)
      
      (let ((new-multiplier (calculate-crop-risk-multiplier success-rate)))
        (map-set crop-risk-profiles
          { crop-type: crop-type }
          {
            total-policies: (get total-policies current-profile),
            total-claims: (get total-claims current-profile),
            success-rate: success-rate,
            risk-multiplier: new-multiplier,
            last-updated: stacks-block-height
          }
        )
        (ok new-multiplier)
      )
    )
  )
)

(define-public (set-seasonal-adjustment (season uint) (adjustment-factor uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= season u4) ERR_INVALID_POLICY)
    (asserts! (and (>= adjustment-factor u50) (<= adjustment-factor u200)) ERR_INVALID_POLICY)
    
    (map-set seasonal-adjustments
      { season: season }
      { adjustment-factor: adjustment-factor, active: true }
    )
    (ok true)
  )
)

(define-public (update-base-premium-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-rate u1) (<= new-rate u20)) ERR_INVALID_POLICY)
    (var-set base-premium-rate new-rate)
    (ok true)
  )
)

(define-private (calculate-dynamic-premium (coverage-amount uint) (duration-blocks uint) (crop-type (string-ascii 50)) (location (string-ascii 100)))
  (let (
    (base-premium (/ (* coverage-amount (var-get base-premium-rate) duration-blocks) u100000))
    (location-risk (get-location-risk-multiplier location))
    (crop-risk (get-crop-risk-multiplier crop-type))
    (seasonal-factor (get-seasonal-factor))
  )
    (/ (* (* (* base-premium location-risk) crop-risk) seasonal-factor) u1000000)
  )
)

(define-private (calculate-location-risk-score (avg-severity uint) (total-claims uint) (total-policies uint))
  (if (is-eq total-policies u0)
    u50
    (let ((claim-rate (/ (* total-claims u100) total-policies)))
      (if (> (+ u20 (/ avg-severity u2) claim-rate) u100)
        u100
        (+ u20 (/ avg-severity u2) claim-rate)
      )
    )
  )
)

(define-private (calculate-crop-risk-multiplier (success-rate uint))
  (if (>= success-rate u80)
    u80
    (if (>= success-rate u60)
      u100
      (if (>= success-rate u40)
        u130
        u160
      )
    )
  )
)

(define-private (get-location-risk-multiplier (location (string-ascii 100)))
  (match (map-get? location-risk-profiles { location: location })
    some-profile (+ u50 (get risk-score some-profile))
    u100
  )
)

(define-private (get-crop-risk-multiplier (crop-type (string-ascii 50)))
  (match (map-get? crop-risk-profiles { crop-type: crop-type })
    some-profile (get risk-multiplier some-profile)
    u100
  )
)

(define-private (get-seasonal-factor)
  (let ((current-season (mod (/ stacks-block-height u2016) u4)))
    (match (map-get? seasonal-adjustments { season: current-season })
      some-adjustment (if (get active some-adjustment) (get adjustment-factor some-adjustment) u100)
      u100
    )
  )
)

(define-read-only (get-location-risk-profile (location (string-ascii 100)))
  (map-get? location-risk-profiles { location: location })
)

(define-read-only (get-crop-risk-profile (crop-type (string-ascii 50)))
  (map-get? crop-risk-profiles { crop-type: crop-type })
)

(define-read-only (estimate-dynamic-premium (coverage-amount uint) (duration-blocks uint) (crop-type (string-ascii 50)) (location (string-ascii 100)))
  (calculate-dynamic-premium coverage-amount duration-blocks crop-type location)
)

(define-read-only (get-current-season)
  (mod (/ stacks-block-height u2016) u4)
)