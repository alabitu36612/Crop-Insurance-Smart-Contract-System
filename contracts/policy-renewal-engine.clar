(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_POLICY_NOT_FOUND (err u104))
(define-constant ERR_INVALID_POLICY (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_TOO_EARLY (err u400))
(define-constant ERR_ALREADY_RENEWED (err u401))

(define-constant RENEWAL_WINDOW u144)
(define-constant FIRST_RENEWAL_DISCOUNT u5)
(define-constant LOYALTY_DISCOUNT u10)

(define-data-var total-renewals uint u0)

(define-map renewal-history
    { policy-id: uint }
    {
        original-policy-id: uint,
        renewal-count: uint,
        last-renewed-at: uint,
        total-renewals-value: uint,
    }
)

(define-map policy-lineage
    { new-policy-id: uint }
    { parent-policy-id: uint }
)

(define-public (renew-policy
        (policy-id uint)
        (new-duration-blocks uint)
    )
    (let (
            (policy-data (unwrap! (contract-call? .Crop-Insurance get-policy policy-id)
                ERR_POLICY_NOT_FOUND
            ))
            (renewal-info (map-get? renewal-history { policy-id: policy-id }))
            (renewal-count (match renewal-info
                some-info (get renewal-count some-info)
                u0
            ))
            (blocks-until-expiry (- (get end-block policy-data) stacks-block-height))
        )
        (begin
            (asserts! (is-eq tx-sender (get farmer policy-data)) ERR_UNAUTHORIZED)
            (asserts! (get is-active policy-data) ERR_INVALID_POLICY)
            (asserts! (not (get claimed policy-data)) ERR_INVALID_POLICY)
            (asserts! (<= blocks-until-expiry RENEWAL_WINDOW) ERR_TOO_EARLY)
            (asserts! (> new-duration-blocks u0) ERR_INVALID_POLICY)

            (let (
                    (base-premium (contract-call? .Crop-Insurance estimate-premium
                        (get coverage-amount policy-data)
                        new-duration-blocks
                    ))
                    (discount-rate (if (is-eq renewal-count u0)
                        FIRST_RENEWAL_DISCOUNT
                        LOYALTY_DISCOUNT
                    ))
                    (discount (/ (* base-premium discount-rate) u100))
                    (final-premium (- base-premium discount))
                )
                (asserts! (>= (stx-get-balance tx-sender) final-premium)
                    ERR_INSUFFICIENT_FUNDS
                )

                (let ((new-policy-id (unwrap-panic (contract-call? .Crop-Insurance purchase-policy
                        (get crop-type policy-data)
                        (get coverage-amount policy-data)
                        new-duration-blocks (get location policy-data)
                    ))))
                    (map-set renewal-history { policy-id: new-policy-id } {
                        original-policy-id: (match renewal-info
                            some-info (get original-policy-id some-info)
                            policy-id
                        ),
                        renewal-count: (+ renewal-count u1),
                        last-renewed-at: stacks-block-height,
                        total-renewals-value: (+
                            (match renewal-info
                                some-info (get total-renewals-value some-info)
                                u0
                            )
                            final-premium
                        ),
                    })

                    (map-set policy-lineage { new-policy-id: new-policy-id } { parent-policy-id: policy-id })
                    (var-set total-renewals (+ (var-get total-renewals) u1))
                    (ok {
                        new-policy-id: new-policy-id,
                        discount-applied: discount,
                    })
                )
            )
        )
    )
)

(define-read-only (get-renewal-info (policy-id uint))
    (map-get? renewal-history { policy-id: policy-id })
)

(define-read-only (get-parent-policy (policy-id uint))
    (map-get? policy-lineage { new-policy-id: policy-id })
)

(define-read-only (calculate-renewal-premium
        (policy-id uint)
        (new-duration-blocks uint)
    )
    (match (contract-call? .Crop-Insurance get-policy policy-id)
        some-policy (let (
                (renewal-info (map-get? renewal-history { policy-id: policy-id }))
                (renewal-count (match renewal-info
                    some-info (get renewal-count some-info)
                    u0
                ))
                (base-premium (contract-call? .Crop-Insurance estimate-premium
                    (get coverage-amount some-policy) new-duration-blocks
                ))
                (discount-rate (if (is-eq renewal-count u0)
                    FIRST_RENEWAL_DISCOUNT
                    LOYALTY_DISCOUNT
                ))
                (discount (/ (* base-premium discount-rate) u100))
            )
            (some (- base-premium discount))
        )
        none
    )
)

(define-read-only (get-total-renewals)
    (var-get total-renewals)
)
