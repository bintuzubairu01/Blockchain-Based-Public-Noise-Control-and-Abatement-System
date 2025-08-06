;; Airport Noise Mitigation Contract
;; Manages programs to reduce aircraft noise impacts on surrounding communities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-AREA-NOT-FOUND (err u401))
(define-constant ERR-PROGRAM-NOT-FOUND (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-INSUFFICIENT-FUNDS (err u404))
(define-constant ERR-ALREADY-COMPENSATED (err u405))

;; Program Status Constants
(define-constant STATUS-PROPOSED u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-ACTIVE u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)

;; Data Variables
(define-data-var next-area-id uint u1)
(define-data-var next-program-id uint u1)
(define-data-var mitigation-fund uint u0)

;; Data Maps
(define-map affected-areas
  { area-id: uint }
  {
    area-name: (string-ascii 100),
    location-x: uint,
    location-y: uint,
    radius: uint,
    population: uint,
    noise-level: uint,
    registered-by: principal,
    compensation-per-resident: uint,
    total-compensated: uint
  }
)

(define-map mitigation-programs
  { program-id: uint }
  {
    program-name: (string-ascii 100),
    area-id: uint,
    description: (string-ascii 500),
    proposed-by: principal,
    budget: uint,
    status: uint,
    start-date: uint,
    end-date: uint,
    effectiveness-rating: uint,
    approved-by: (optional principal)
  }
)

(define-map airport-authorities
  { authority: principal }
  {
    authorized: bool,
    programs-managed: uint,
    total-budget-allocated: uint
  }
)

(define-map flight-restrictions
  { restriction-id: uint }
  {
    area-id: uint,
    restriction-type: (string-ascii 50),
    time-start: uint,
    time-end: uint,
    altitude-min: uint,
    flight-path-deviation: uint,
    active: bool
  }
)

(define-map resident-compensation
  { area-id: uint, resident: principal }
  {
    compensation-amount: uint,
    payment-date: uint,
    payment-reason: (string-ascii 200),
    paid: bool
  }
)

;; Authorization Functions
(define-public (authorize-airport-authority (authority principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set airport-authorities
      { authority: authority }
      {
        authorized: true,
        programs-managed: u0,
        total-budget-allocated: u0
      }
    ))
  )
)

(define-public (revoke-airport-authority (authority principal))
  (let
    (
      (authority-data (unwrap! (map-get? airport-authorities { authority: authority }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set airport-authorities
      { authority: authority }
      (merge authority-data { authorized: false })
    ))
  )
)

;; Fund Management
(define-public (deposit-mitigation-funds (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set mitigation-fund (+ (var-get mitigation-fund) amount))
    (ok amount)
  )
)

;; Area Registration
(define-public (register-affected-area
  (area-name (string-ascii 100))
  (location-x uint)
  (location-y uint)
  (radius uint)
  (population uint)
  (noise-level uint)
  (compensation-per-resident uint))
  (let
    (
      (area-id (var-get next-area-id))
    )
    (asserts! (> (len area-name) u0) ERR-INVALID-INPUT)
    (asserts! (and (> location-x u0) (> location-y u0)) ERR-INVALID-INPUT)
    (asserts! (and (> radius u0) (> population u0)) ERR-INVALID-INPUT)
    (asserts! (and (> noise-level u0) (> compensation-per-resident u0)) ERR-INVALID-INPUT)

    (map-set affected-areas
      { area-id: area-id }
      {
        area-name: area-name,
        location-x: location-x,
        location-y: location-y,
        radius: radius,
        population: population,
        noise-level: noise-level,
        registered-by: tx-sender,
        compensation-per-resident: compensation-per-resident,
        total-compensated: u0
      }
    )

    (var-set next-area-id (+ area-id u1))
    (ok area-id)
  )
)

;; Mitigation Program Proposal
(define-public (propose-mitigation-program
  (program-name (string-ascii 100))
  (area-id uint)
  (description (string-ascii 500))
  (budget uint)
  (start-date uint)
  (end-date uint))
  (let
    (
      (program-id (var-get next-program-id))
      (area (unwrap! (map-get? affected-areas { area-id: area-id }) ERR-AREA-NOT-FOUND))
    )
    (asserts! (> (len program-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u10) ERR-INVALID-INPUT)
    (asserts! (> budget u0) ERR-INVALID-INPUT)
    (asserts! (> end-date start-date) ERR-INVALID-INPUT)

    (map-set mitigation-programs
      { program-id: program-id }
      {
        program-name: program-name,
        area-id: area-id,
        description: description,
        proposed-by: tx-sender,
        budget: budget,
        status: STATUS-PROPOSED,
        start-date: start-date,
        end-date: end-date,
        effectiveness-rating: u0,
        approved-by: none
      }
    )

    (var-set next-program-id (+ program-id u1))
    (ok program-id)
  )
)

;; Program Approval
(define-public (approve-mitigation-program (program-id uint))
  (let
    (
      (program (unwrap! (map-get? mitigation-programs { program-id: program-id }) ERR-PROGRAM-NOT-FOUND))
      (authority-data (unwrap! (map-get? airport-authorities { authority: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (get authorized authority-data) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status program) STATUS-PROPOSED) ERR-INVALID-INPUT)
    (asserts! (<= (get budget program) (var-get mitigation-fund)) ERR-INSUFFICIENT-FUNDS)

    ;; Update program
    (map-set mitigation-programs
      { program-id: program-id }
      (merge program {
        status: STATUS-APPROVED,
        approved-by: (some tx-sender)
      })
    )

    ;; Update authority stats
    (map-set airport-authorities
      { authority: tx-sender }
      (merge authority-data {
        programs-managed: (+ (get programs-managed authority-data) u1),
        total-budget-allocated: (+ (get total-budget-allocated authority-data) (get budget program))
      })
    )

    ;; Deduct from mitigation fund
    (var-set mitigation-fund (- (var-get mitigation-fund) (get budget program)))

    (ok true)
  )
)

;; Compensate Residents
(define-public (compensate-resident (area-id uint) (resident principal) (payment-reason (string-ascii 200)))
  (let
    (
      (area (unwrap! (map-get? affected-areas { area-id: area-id }) ERR-AREA-NOT-FOUND))
      (compensation-amount (get compensation-per-resident area))
      (existing-compensation (map-get? resident-compensation { area-id: area-id, resident: resident }))
    )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (match (map-get? airport-authorities { authority: tx-sender })
                    data (get authorized data)
                    false)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-compensation) ERR-ALREADY-COMPENSATED)
    (asserts! (> (len payment-reason) u10) ERR-INVALID-INPUT)

    ;; Transfer compensation
    (try! (as-contract (stx-transfer? compensation-amount tx-sender resident)))

    ;; Record compensation
    (map-set resident-compensation
      { area-id: area-id, resident: resident }
      {
        compensation-amount: compensation-amount,
        payment-date: block-height,
        payment-reason: payment-reason,
        paid: true
      }
    )

    ;; Update area stats
    (map-set affected-areas
      { area-id: area-id }
      (merge area { total-compensated: (+ (get total-compensated area) compensation-amount) })
    )

    (ok compensation-amount)
  )
)

;; Update Program Effectiveness
(define-public (update-program-effectiveness (program-id uint) (effectiveness-rating uint))
  (let
    (
      (program (unwrap! (map-get? mitigation-programs { program-id: program-id }) ERR-PROGRAM-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get proposed-by program))
                  (is-eq (some tx-sender) (get approved-by program))) ERR-NOT-AUTHORIZED)
    (asserts! (<= effectiveness-rating u100) ERR-INVALID-INPUT)

    (ok (map-set mitigation-programs
      { program-id: program-id }
      (merge program { effectiveness-rating: effectiveness-rating })
    ))
  )
)

;; Read-only Functions
(define-read-only (get-affected-area-info (area-id uint))
  (map-get? affected-areas { area-id: area-id })
)

(define-read-only (get-mitigation-program-info (program-id uint))
  (map-get? mitigation-programs { program-id: program-id })
)

(define-read-only (get-airport-authority-info (authority principal))
  (map-get? airport-authorities { authority: authority })
)

(define-read-only (get-resident-compensation-info (area-id uint) (resident principal))
  (map-get? resident-compensation { area-id: area-id, resident: resident })
)

(define-read-only (get-mitigation-fund-balance)
  (var-get mitigation-fund)
)

(define-read-only (get-next-area-id)
  (var-get next-area-id)
)

(define-read-only (get-next-program-id)
  (var-get next-program-id)
)

(define-read-only (is-airport-authority-authorized (authority principal))
  (match (map-get? airport-authorities { authority: authority })
    data (get authorized data)
    false
  )
)
