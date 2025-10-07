(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_BUNDLE_NOT_FOUND (err u300))
(define-constant ERR_POLICY_NOT_FOUND (err u104))
(define-constant ERR_INVALID_BUNDLE (err u301))
(define-constant ERR_BUNDLE_FULL (err u302))
(define-constant ERR_DUPLICATE_POLICY (err u303))

(define-constant MAX_POLICIES_PER_BUNDLE u10)
(define-constant BUNDLE_DISCOUNT_RATE u15)
(define-constant MIN_BUNDLE_SIZE u3)

(define-data-var next-bundle-id uint u1)

(define-map policy-bundles
  { bundle-id: uint }
  {
    owner: principal,
    bundle-name: (string-ascii 50),
    policy-ids: (list 10 uint),
    created-at: uint,
    total-coverage: uint,
    total-premium: uint,
    discount-applied: uint,
    is-active: bool
  }
)

(define-map farmer-bundles
  { farmer: principal }
  { bundle-ids: (list 5 uint) }
)

(define-map policy-bundle-index
  { policy-id: uint }
  { bundle-id: uint }
)

(define-public (create-bundle (bundle-name (string-ascii 50)) (policy-ids (list 10 uint)))
  (let (
    (bundle-id (var-get next-bundle-id))
    (policy-count (len policy-ids))
  )
    (begin
      (asserts! (>= policy-count MIN_BUNDLE_SIZE) ERR_INVALID_BUNDLE)
      (asserts! (<= policy-count MAX_POLICIES_PER_BUNDLE) ERR_BUNDLE_FULL)
      
      (let (
        (bundle-totals (fold calculate-bundle-totals policy-ids { total-coverage: u0, total-premium: u0, valid: true }))
      )
        (asserts! (get valid bundle-totals) ERR_POLICY_NOT_FOUND)
        
        (let (
          (discount (/ (* (get total-premium bundle-totals) BUNDLE_DISCOUNT_RATE) u100))
          (final-premium (- (get total-premium bundle-totals) discount))
        )
          (map-set policy-bundles
            { bundle-id: bundle-id }
            {
              owner: tx-sender,
              bundle-name: bundle-name,
              policy-ids: policy-ids,
              created-at: stacks-block-height,
              total-coverage: (get total-coverage bundle-totals),
              total-premium: final-premium,
              discount-applied: discount,
              is-active: true
            }
          )
          
          (map register-policy-to-bundle policy-ids (list bundle-id))
          
          (let ((current-bundles (default-to { bundle-ids: (list) } (map-get? farmer-bundles { farmer: tx-sender }))))
            (map-set farmer-bundles
              { farmer: tx-sender }
              { bundle-ids: (unwrap! (as-max-len? (append (get bundle-ids current-bundles) bundle-id) u5) ERR_BUNDLE_FULL) }
            )
          )
          
          (var-set next-bundle-id (+ bundle-id u1))
          (ok bundle-id)
        )
      )
    )
  )
)

(define-private (calculate-bundle-totals (policy-id uint) (acc { total-coverage: uint, total-premium: uint, valid: bool }))
  (if (not (get valid acc))
    acc
    (match (contract-call? .Crop-Insurance get-policy policy-id)
      some-policy (if (is-eq (get farmer some-policy) tx-sender)
        {
          total-coverage: (+ (get total-coverage acc) (get coverage-amount some-policy)),
          total-premium: (+ (get total-premium acc) (get premium-paid some-policy)),
          valid: true
        }
        { total-coverage: u0, total-premium: u0, valid: false }
      )
      { total-coverage: u0, total-premium: u0, valid: false }
    )
  )
)

(define-private (register-policy-to-bundle (policy-id uint) (bundle-id uint))
  (map-set policy-bundle-index { policy-id: policy-id } { bundle-id: bundle-id })
)

(define-read-only (get-bundle (bundle-id uint))
  (map-get? policy-bundles { bundle-id: bundle-id })
)

(define-read-only (get-farmer-bundles (farmer principal))
  (map-get? farmer-bundles { farmer: farmer })
)

(define-read-only (get-policy-bundle (policy-id uint))
  (map-get? policy-bundle-index { policy-id: policy-id })
)
