(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-DOMAIN-OWNER (err u101))
(define-constant ERR-DOMAIN-NOT-FOUND (err u102))
(define-constant ERR-SUBDOMAIN-EXISTS (err u103))
(define-constant ERR-SUBDOMAIN-NOT-FOUND (err u104))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u105))
(define-constant ERR-DOMAIN-EXPIRED (err u106))
(define-constant ERR-INVALID-NAME (err u107))
(define-constant ERR-TRANSFER-FAILED (err u108))

(define-data-var domain-registration-fee uint u1000000)
(define-data-var subdomain-registration-fee uint u500000)
(define-data-var contract-balance uint u0)

(define-map domains
  { name: (string-ascii 64) }
  { 
    owner: principal, 
    expiry: uint, 
    created-at: uint,
    subdomain-count: uint
  }
)

(define-map subdomains
  { domain: (string-ascii 64), subdomain: (string-ascii 64) }
  { 
    owner: principal, 
    created-at: uint,
    parent-domain: (string-ascii 64)
  }
)

(define-map domain-revenues
  { domain: (string-ascii 64) }
  { total-earned: uint }
)

(define-read-only (get-domain-info (name (string-ascii 64)))
  (map-get? domains { name: name })
)

(define-read-only (get-subdomain-info (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (map-get? subdomains { domain: domain, subdomain: subdomain })
)

(define-read-only (get-domain-revenue (domain (string-ascii 64)))
  (default-to 
    { total-earned: u0 }
    (map-get? domain-revenues { domain: domain })
  )
)

(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

(define-read-only (get-domain-registration-fee)
  (var-get domain-registration-fee)
)

(define-read-only (get-subdomain-registration-fee)
  (var-get subdomain-registration-fee)
)

(define-read-only (is-domain-expired (name (string-ascii 64)))
  (match (get-domain-info name)
    domain-info (> stacks-block-height (get expiry domain-info))
    true
  )
)

(define-read-only (is-valid-name (name (string-ascii 64)))
  (and 
    (> (len name) u0)
    (< (len name) u65)
    (is-eq (index-of name " ") none)
  )
)

(define-private (is-domain-owner (domain (string-ascii 64)) (user principal))
  (match (get-domain-info domain)
    domain-info (is-eq (get owner domain-info) user)
    false
  )
)

(define-private (update-domain-revenue (domain (string-ascii 64)) (amount uint))
  (let ((current-revenue (get total-earned (get-domain-revenue domain))))
    (map-set domain-revenues 
      { domain: domain }
      { total-earned: (+ current-revenue amount) }
    )
  )
)

(define-public (register-domain (name (string-ascii 64)) (duration uint))
  (let ((fee (var-get domain-registration-fee))
        (expiry (+ stacks-block-height duration)))
    (asserts! (is-valid-name name) ERR-INVALID-NAME)
    (asserts! (is-none (get-domain-info name)) ERR-DOMAIN-EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) fee))
    
    (map-set domains
      { name: name }
      { 
        owner: tx-sender,
        expiry: expiry,
        created-at: stacks-block-height,
        subdomain-count: u0
      }
    )
    
    (map-set domain-revenues
      { domain: name }
      { total-earned: u0 }
    )
    
    (ok true)
  )
)

(define-public (register-subdomain (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (let ((fee (var-get subdomain-registration-fee))
        (domain-info (unwrap! (get-domain-info domain) ERR-DOMAIN-NOT-FOUND)))
    
    (asserts! (is-valid-name subdomain) ERR-INVALID-NAME)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (is-none (get-subdomain-info domain subdomain)) ERR-SUBDOMAIN-EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (stx-transfer? fee tx-sender (get owner domain-info)))
    (update-domain-revenue domain fee)
    
    (map-set subdomains
      { domain: domain, subdomain: subdomain }
      { 
        owner: tx-sender,
        created-at: stacks-block-height,
        parent-domain: domain
      }
    )
    
    (map-set domains
      { name: domain }
      (merge domain-info { subdomain-count: (+ (get subdomain-count domain-info) u1) })
    )
    
    (ok true)
  )
)

(define-public (transfer-domain (name (string-ascii 64)) (new-owner principal))
  (let ((domain-info (unwrap! (get-domain-info name) ERR-DOMAIN-NOT-FOUND)))
    (asserts! (is-eq (get owner domain-info) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (not (is-domain-expired name)) ERR-DOMAIN-EXPIRED)
    
    (map-set domains
      { name: name }
      (merge domain-info { owner: new-owner })
    )
    
    (ok true)
  )
)

(define-public (transfer-subdomain (domain (string-ascii 64)) (subdomain (string-ascii 64)) (new-owner principal))
  (let ((subdomain-info (unwrap! (get-subdomain-info domain subdomain) ERR-SUBDOMAIN-NOT-FOUND)))
    (asserts! (is-eq (get owner subdomain-info) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    
    (map-set subdomains
      { domain: domain, subdomain: subdomain }
      (merge subdomain-info { owner: new-owner })
    )
    
    (ok true)
  )
)

(define-public (renew-domain (name (string-ascii 64)) (additional-duration uint))
  (let ((domain-info (unwrap! (get-domain-info name) ERR-DOMAIN-NOT-FOUND))
        (fee (var-get domain-registration-fee)))
    
    (asserts! (is-eq (get owner domain-info) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) fee))
    
    (map-set domains
      { name: name }
      (merge domain-info { expiry: (+ (get expiry domain-info) additional-duration) })
    )
    
    (ok true)
  )
)

(define-public (set-domain-registration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set domain-registration-fee new-fee)
    (ok true)
  )
)

(define-public (set-subdomain-registration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set subdomain-registration-fee new-fee)
    (ok true)
  )
)

(define-public (withdraw-contract-balance (amount uint))
  (let ((balance (var-get contract-balance)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= amount balance) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (var-set contract-balance (- balance amount))
    
    (ok true)
  )
)

(define-public (emergency-transfer-domain (name (string-ascii 64)) (new-owner principal))
  (let ((domain-info (unwrap! (get-domain-info name) ERR-DOMAIN-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set domains
      { name: name }
      (merge domain-info { owner: new-owner })
    )
    
    (ok true)
  )
)

(define-constant ERR-DOMAIN-EXISTS (err u109))
(define-constant ERR-LISTING-NOT-FOUND (err u110))
(define-constant ERR-LISTING-EXISTS (err u111))
(define-constant ERR-CANNOT-BUY-OWN-LISTING (err u112))
(define-constant ERR-LISTING-EXPIRED (err u113))

(define-data-var marketplace-fee-percent uint u5)

(define-map domain-listings
  { domain: (string-ascii 64) }
  { 
    seller: principal,
    price: uint,
    listed-at: uint,
    expiry: uint
  }
)

(define-map subdomain-listings
  { domain: (string-ascii 64), subdomain: (string-ascii 64) }
  { 
    seller: principal,
    price: uint,
    listed-at: uint,
    expiry: uint
  }
)

(define-read-only (get-domain-listing (domain (string-ascii 64)))
  (map-get? domain-listings { domain: domain })
)

(define-read-only (get-subdomain-listing (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (map-get? subdomain-listings { domain: domain, subdomain: subdomain })
)

(define-read-only (get-marketplace-fee-percent)
  (var-get marketplace-fee-percent)
)

(define-read-only (is-listing-expired (listed-at uint) (expiry uint))
  (> stacks-block-height (+ listed-at expiry))
)

(define-private (calculate-marketplace-fee (price uint))
  (/ (* price (var-get marketplace-fee-percent)) u100)
)

(define-public (list-domain-for-sale (domain (string-ascii 64)) (price uint) (duration uint))
  (let ((domain-info (unwrap! (get-domain-info domain) ERR-DOMAIN-NOT-FOUND)))
    (asserts! (is-eq (get owner domain-info) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (is-none (get-domain-listing domain)) ERR-LISTING-EXISTS)
    (asserts! (> price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set domain-listings
      { domain: domain }
      { 
        seller: tx-sender,
        price: price,
        listed-at: stacks-block-height,
        expiry: duration
      }
    )
    
    (ok true)
  )
)

(define-public (list-subdomain-for-sale (domain (string-ascii 64)) (subdomain (string-ascii 64)) (price uint) (duration uint))
  (let ((subdomain-info (unwrap! (get-subdomain-info domain subdomain) ERR-SUBDOMAIN-NOT-FOUND)))
    (asserts! (is-eq (get owner subdomain-info) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (is-none (get-subdomain-listing domain subdomain)) ERR-LISTING-EXISTS)
    (asserts! (> price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set subdomain-listings
      { domain: domain, subdomain: subdomain }
      { 
        seller: tx-sender,
        price: price,
        listed-at: stacks-block-height,
        expiry: duration
      }
    )
    
    (ok true)
  )
)

(define-public (buy-domain (domain (string-ascii 64)))
  (let ((listing (unwrap! (get-domain-listing domain) ERR-LISTING-NOT-FOUND))
        (domain-info (unwrap! (get-domain-info domain) ERR-DOMAIN-NOT-FOUND))
        (marketplace-fee (calculate-marketplace-fee (get price listing)))
        (seller-amount (- (get price listing) marketplace-fee)))
    
    (asserts! (not (is-eq tx-sender (get seller listing))) ERR-CANNOT-BUY-OWN-LISTING)
    (asserts! (not (is-listing-expired (get listed-at listing) (get expiry listing))) ERR-LISTING-EXPIRED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (>= (stx-get-balance tx-sender) (get price listing)) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (stx-transfer? seller-amount tx-sender (get seller listing)))
    (try! (stx-transfer? marketplace-fee tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) marketplace-fee))
    
    (map-set domains
      { name: domain }
      (merge domain-info { owner: tx-sender })
    )
    
    (map-delete domain-listings { domain: domain })
    
    (ok true)
  )
)

(define-public (buy-subdomain (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (let ((listing (unwrap! (get-subdomain-listing domain subdomain) ERR-LISTING-NOT-FOUND))
        (subdomain-info (unwrap! (get-subdomain-info domain subdomain) ERR-SUBDOMAIN-NOT-FOUND))
        (marketplace-fee (calculate-marketplace-fee (get price listing)))
        (seller-amount (- (get price listing) marketplace-fee)))
    
    (asserts! (not (is-eq tx-sender (get seller listing))) ERR-CANNOT-BUY-OWN-LISTING)
    (asserts! (not (is-listing-expired (get listed-at listing) (get expiry listing))) ERR-LISTING-EXPIRED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (>= (stx-get-balance tx-sender) (get price listing)) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (stx-transfer? seller-amount tx-sender (get seller listing)))
    (try! (stx-transfer? marketplace-fee tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) marketplace-fee))
    
    (map-set subdomains
      { domain: domain, subdomain: subdomain }
      (merge subdomain-info { owner: tx-sender })
    )
    
    (map-delete subdomain-listings { domain: domain, subdomain: subdomain })
    
    (ok true)
  )
)

(define-public (cancel-domain-listing (domain (string-ascii 64)))
  (let ((listing (unwrap! (get-domain-listing domain) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq (get seller listing) tx-sender) ERR-NOT-DOMAIN-OWNER)
    
    (map-delete domain-listings { domain: domain })
    
    (ok true)
  )
)

(define-public (cancel-subdomain-listing (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (let ((listing (unwrap! (get-subdomain-listing domain subdomain) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq (get seller listing) tx-sender) ERR-NOT-DOMAIN-OWNER)
    
    (map-delete subdomain-listings { domain: domain, subdomain: subdomain })
    
    (ok true)
  )
)

(define-public (update-domain-listing-price (domain (string-ascii 64)) (new-price uint))
  (let ((listing (unwrap! (get-domain-listing domain) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq (get seller listing) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (> new-price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set domain-listings
      { domain: domain }
      (merge listing { price: new-price })
    )
    
    (ok true)
  )
)

(define-public (update-subdomain-listing-price (domain (string-ascii 64)) (subdomain (string-ascii 64)) (new-price uint))
  (let ((listing (unwrap! (get-subdomain-listing domain subdomain) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq (get seller listing) tx-sender) ERR-NOT-DOMAIN-OWNER)
    (asserts! (> new-price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set subdomain-listings
      { domain: domain, subdomain: subdomain }
      (merge listing { price: new-price })
    )
    
    (ok true)
  )
)

(define-public (set-marketplace-fee-percent (new-fee-percent uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-fee-percent u50) ERR-INSUFFICIENT-PAYMENT)
    (var-set marketplace-fee-percent new-fee-percent)
    (ok true)
  )
)

(define-constant ERR-NOT-AUTHORIZED (err u114))
(define-constant ERR-RECORD-NOT-FOUND (err u115))

(define-map address-records
  { domain: (string-ascii 64), subdomain: (optional (string-ascii 64)), record-type: (string-ascii 32) }
  { address-value: (string-ascii 128), set-at: uint }
)

(define-map text-records
  { domain: (string-ascii 64), subdomain: (optional (string-ascii 64)), record-type: (string-ascii 32) }
  { text-value: (string-ascii 256), set-at: uint }
)

(define-map content-records
  { domain: (string-ascii 64), subdomain: (optional (string-ascii 64)) }
  { content-hash: (string-ascii 128), set-at: uint }
)

(define-private (is-domain-or-subdomain-owner (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (user principal))
  (match subdomain
    sub-name (match (get-subdomain-info domain sub-name)
      subdomain-info (is-eq (get owner subdomain-info) user)
      false
    )
    (match (get-domain-info domain)
      domain-info (is-eq (get owner domain-info) user)
      false
    )
  )
)

(define-read-only (get-address-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)))
  (match (map-get? address-records { domain: domain, subdomain: subdomain, record-type: record-type })
    record (some record)
    (match subdomain
      sub-name none
      (map-get? address-records { domain: domain, subdomain: none, record-type: record-type })
    )
  )
)

(define-read-only (get-text-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)))
  (match (map-get? text-records { domain: domain, subdomain: subdomain, record-type: record-type })
    record (some record)
    (match subdomain
      sub-name none
      (map-get? text-records { domain: domain, subdomain: none, record-type: record-type })
    )
  )
)

(define-read-only (get-content-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))))
  (match (map-get? content-records { domain: domain, subdomain: subdomain })
    record (some record)
    (match subdomain
      sub-name none
      (map-get? content-records { domain: domain, subdomain: none })
    )
  )
)

(define-map domain-operators
  { domain: (string-ascii 64), operator: principal }
  { set-at: uint }
)

(define-read-only (is-domain-operator (domain (string-ascii 64)) (operator principal))
  (is-some (map-get? domain-operators { domain: domain, operator: operator }))
)

(define-private (is-authorized (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (user principal))
  (or (is-domain-or-subdomain-owner domain subdomain user) (is-domain-operator domain user))
)

(define-public (add-domain-operator (domain (string-ascii 64)) (operator principal))
  (begin
    (asserts! (is-domain-owner domain tx-sender) ERR-NOT-DOMAIN-OWNER)
    (map-set domain-operators { domain: domain, operator: operator } { set-at: stacks-block-height })
    (ok true)
  )
)

(define-public (remove-domain-operator (domain (string-ascii 64)) (operator principal))
  (begin
    (asserts! (is-domain-owner domain tx-sender) ERR-NOT-DOMAIN-OWNER)
    (map-delete domain-operators { domain: domain, operator: operator })
    (ok true)
  )
)

(define-public (set-address-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)) (address-value (string-ascii 128)))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (> (len address-value) u0) ERR-INVALID-NAME)
    
    (map-set address-records
      { domain: domain, subdomain: subdomain, record-type: record-type }
      { address-value: address-value, set-at: stacks-block-height }
    )
    
    (ok true)
  )
)

(define-public (set-text-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)) (text-value (string-ascii 256)))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (> (len text-value) u0) ERR-INVALID-NAME)
    
    (map-set text-records
      { domain: domain, subdomain: subdomain, record-type: record-type }
      { text-value: text-value, set-at: stacks-block-height }
    )
    
    (ok true)
  )
)

(define-public (set-content-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (content-hash (string-ascii 128)))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    (asserts! (> (len content-hash) u0) ERR-INVALID-NAME)
    
    (map-set content-records
      { domain: domain, subdomain: subdomain }
      { content-hash: content-hash, set-at: stacks-block-height }
    )
    
    (ok true)
  )
)

(define-public (delete-address-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-delete address-records { domain: domain, subdomain: subdomain, record-type: record-type })
    
    (ok true)
  )
)

(define-public (delete-text-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (record-type (string-ascii 32)))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-delete text-records { domain: domain, subdomain: subdomain, record-type: record-type })
    
    (ok true)
  )
)

(define-public (delete-content-record (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))))
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-delete content-records { domain: domain, subdomain: subdomain })
    
    (ok true)
  )
)

(define-public (set-multiple-records 
  (domain (string-ascii 64)) 
  (subdomain (optional (string-ascii 64))) 
  (stx-address (optional (string-ascii 128)))
  (btc-address (optional (string-ascii 128)))
  (email (optional (string-ascii 256)))
  (website (optional (string-ascii 256)))
  (content-hash (optional (string-ascii 128)))
)
  (begin
    (asserts! (is-authorized domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    
    (match stx-address
      addr (try! (set-address-record domain subdomain "stx" addr))
      true
    )
    
    (match btc-address
      addr (try! (set-address-record domain subdomain "btc" addr))
      true
    )
    
    (match email
      mail (try! (set-text-record domain subdomain "email" mail))
      true
    )
    
    (match website
      site (try! (set-text-record domain subdomain "website" site))
      true
    )
    
    (match content-hash
      hash (try! (set-content-record domain subdomain hash))
      true
    )
    
    (ok true)
  )
)

(define-constant ERR-PRIMARY-NAME-NOT-SET (err u116))
(define-constant ERR-NAME-MISMATCH (err u117))

(define-map reverse-records
  { address: principal }
  { 
    domain: (string-ascii 64), 
    subdomain: (optional (string-ascii 64)),
    set-at: uint
  }
)

(define-read-only (get-primary-name (address principal))
  (map-get? reverse-records { address: address })
)

(define-read-only (resolve-principal (address principal))
  (match (get-primary-name address)
    record (match (get subdomain record)
      sub-name (some (concat (concat (get domain record) ".") sub-name))
      (some (get domain record))
    )
    none
  )
)

(define-read-only (get-name-owner (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))))
  (match subdomain
    sub-name (match (get-subdomain-info domain sub-name)
      info (some (get owner info))
      none
    )
    (match (get-domain-info domain)
      info (some (get owner info))
      none
    )
  )
)

(define-private (verify-name-ownership (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))) (claimer principal))
  (match (get-name-owner domain subdomain)
    owner (is-eq owner claimer)
    false
  )
)

(define-public (set-primary-name (domain (string-ascii 64)) (subdomain (optional (string-ascii 64))))
  (begin
    (asserts! (verify-name-ownership domain subdomain tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-domain-expired domain)) ERR-DOMAIN-EXPIRED)
    
    (map-set reverse-records
      { address: tx-sender }
      { 
        domain: domain, 
        subdomain: subdomain,
        set-at: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-public (clear-primary-name)
  (begin
    (asserts! (is-some (get-primary-name tx-sender)) ERR-PRIMARY-NAME-NOT-SET)
    
    (map-delete reverse-records { address: tx-sender })
    
    (ok true)
  )
)

(define-public (update-primary-name (new-domain (string-ascii 64)) (new-subdomain (optional (string-ascii 64))))
  (begin
    (asserts! (is-some (get-primary-name tx-sender)) ERR-PRIMARY-NAME-NOT-SET)
    (try! (set-primary-name new-domain new-subdomain))
    
    (ok true)
  )
)

(define-read-only (has-primary-name (address principal))
  (is-some (get-primary-name address))
)

(define-read-only (get-display-name (address principal))
  (match (resolve-principal address)
    name name
    ""
  )
)

(define-read-only (batch-resolve-principals (addresses (list 10 principal)))
  (map resolve-principal addresses)
)

(define-public (set-primary-name-for-domain (domain (string-ascii 64)))
  (set-primary-name domain none)
)

(define-public (set-primary-name-for-subdomain (domain (string-ascii 64)) (subdomain (string-ascii 64)))
  (set-primary-name domain (some subdomain))
)
