(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_POLICY_NOT_FOUND (err u104))
(define-constant ERR_INVALID_POLICY (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_ALREADY_LISTED (err u109))
(define-constant ERR_NOT_LISTED (err u110))
(define-constant ERR_CANNOT_TRANSFER (err u111))

(define-data-var transfer-fee-rate uint u300)
(define-data-var next-listing-id uint u1)

(define-map policy-listings
  { listing-id: uint }
  {
    policy-id: uint,
    seller: principal,
    asking-price: uint,
    listed-at: uint,
    is-active: bool
  }
)

(define-map active-listings
  { policy-id: uint }
  { listing-id: uint }
)

(define-map transfer-history
  { policy-id: uint, transfer-id: uint }
  {
    from-farmer: principal,
    to-farmer: principal,
    transfer-price: uint,
    transfer-block: uint,
    fee-paid: uint
  }
)

(define-map policy-transfer-count
  { policy-id: uint }
  { count: uint }
)

(define-public (list-policy-for-sale (policy-id uint) (asking-price uint))
  (let (
    (listing-id (var-get next-listing-id))
    (policy-data (unwrap! (contract-call? .Crop-Insurance get-policy policy-id) ERR_POLICY_NOT_FOUND))
  )
    (begin
      (asserts! (is-eq tx-sender (get farmer policy-data)) ERR_UNAUTHORIZED)
      (asserts! (get is-active policy-data) ERR_INVALID_POLICY)
      (asserts! (not (get claimed policy-data)) ERR_INVALID_POLICY)
      (asserts! (> asking-price u0) ERR_INVALID_POLICY)
      (asserts! (is-none (map-get? active-listings { policy-id: policy-id })) ERR_ALREADY_LISTED)
      
      (map-set policy-listings
        { listing-id: listing-id }
        {
          policy-id: policy-id,
          seller: tx-sender,
          asking-price: asking-price,
          listed-at: stacks-block-height,
          is-active: true
        }
      )
      
      (map-set active-listings
        { policy-id: policy-id }
        { listing-id: listing-id }
      )
      
      (var-set next-listing-id (+ listing-id u1))
      (ok listing-id)
    )
  )
)

(define-public (purchase-listed-policy (listing-id uint))
  (let (
    (listing-data (unwrap! (map-get? policy-listings { listing-id: listing-id }) ERR_NOT_LISTED))
    (policy-data (unwrap! (contract-call? .Crop-Insurance get-policy (get policy-id listing-data)) ERR_POLICY_NOT_FOUND))
    (asking-price (get asking-price listing-data))
    (transfer-fee (/ (* asking-price (var-get transfer-fee-rate)) u10000))
    (seller-amount (- asking-price transfer-fee))
  )
    (begin
      (asserts! (get is-active listing-data) ERR_NOT_LISTED)
      (asserts! (not (is-eq tx-sender (get seller listing-data))) ERR_UNAUTHORIZED)
      (asserts! (>= (stx-get-balance tx-sender) asking-price) ERR_INSUFFICIENT_FUNDS)
      
      (try! (stx-transfer? seller-amount tx-sender (get seller listing-data)))
      (try! (stx-transfer? transfer-fee tx-sender (as-contract tx-sender)))
      
      (try! (contract-call? .Crop-Insurance transfer-policy-ownership 
        (get policy-id listing-data) 
        (get seller listing-data) 
        tx-sender
      ))
      
      (map-set policy-listings
        { listing-id: listing-id }
        (merge listing-data { is-active: false })
      )
      
      (map-delete active-listings { policy-id: (get policy-id listing-data) })
      
      (let ((transfer-count (default-to { count: u0 } (map-get? policy-transfer-count { policy-id: (get policy-id listing-data) }))))
        (map-set transfer-history
          { policy-id: (get policy-id listing-data), transfer-id: (get count transfer-count) }
          {
            from-farmer: (get seller listing-data),
            to-farmer: tx-sender,
            transfer-price: asking-price,
            transfer-block: stacks-block-height,
            fee-paid: transfer-fee
          }
        )
        
        (map-set policy-transfer-count
          { policy-id: (get policy-id listing-data) }
          { count: (+ (get count transfer-count) u1) }
        )
      )
      
      (ok true)
    )
  )
)

(define-public (cancel-listing (listing-id uint))
  (let ((listing-data (unwrap! (map-get? policy-listings { listing-id: listing-id }) ERR_NOT_LISTED)))
    (begin
      (asserts! (is-eq tx-sender (get seller listing-data)) ERR_UNAUTHORIZED)
      (asserts! (get is-active listing-data) ERR_NOT_LISTED)
      
      (map-set policy-listings
        { listing-id: listing-id }
        (merge listing-data { is-active: false })
      )
      
      (map-delete active-listings { policy-id: (get policy-id listing-data) })
      (ok true)
    )
  )
)

(define-read-only (get-listing (listing-id uint))
  (map-get? policy-listings { listing-id: listing-id })
)

(define-read-only (get-policy-listing (policy-id uint))
  (map-get? active-listings { policy-id: policy-id })
)

(define-read-only (get-transfer-history (policy-id uint) (transfer-id uint))
  (map-get? transfer-history { policy-id: policy-id, transfer-id: transfer-id })
)

(define-read-only (get-policy-transfer-count (policy-id uint))
  (default-to { count: u0 } (map-get? policy-transfer-count { policy-id: policy-id }))
)
