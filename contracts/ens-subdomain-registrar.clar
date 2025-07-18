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
