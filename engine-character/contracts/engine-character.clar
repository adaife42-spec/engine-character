;; ChainForge Gaming Engine
;; Revolutionary decentralized gaming ecosystem with character progression

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-character-not-found (err u103))
(define-constant err-trait-not-found (err u104))
(define-constant err-invalid-trait-value (err u105))
(define-constant err-game-not-registered (err u106))
(define-constant err-unauthorized-game (err u107))

;; Data Variables
(define-data-var next-character-id uint u1)
(define-data-var next-trait-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var forge-token-supply uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Data Maps
(define-map characters
  { character-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    level: uint,
    experience: uint,
    created-at: uint,
    last-active: uint,
    total-games-played: uint,
    cross-chain-hash: (buff 32)
  }
)

(define-map character-traits
  { character-id: uint, trait-id: uint }
  {
    trait-type: (string-ascii 30),
    trait-value: uint,
    rarity-tier: uint,
    evolution-level: uint,
    unlock-requirements: (string-ascii 100)
  }
)

(define-map trait-definitions
  { trait-id: uint }
  {
    trait-name: (string-ascii 50),
    trait-category: (string-ascii 30),
    base-value: uint,
    max-evolution: uint,
    creator: principal,
    creation-block: uint
  }
)

(define-map forge-balances
  { holder: principal }
  { balance: uint }
)

(define-map registered-games
  { game-id: (string-ascii 50) }
  {
    developer: principal,
    name: (string-ascii 100),
    integration-fee: uint,
    active: bool,
    total-players: uint
  }
)

(define-map character-game-progress
  { character-id: uint, game-id: (string-ascii 50) }
  {
    achievements: uint,
    playtime: uint,
    last-session: uint,
    game-specific-data: (string-ascii 500)
  }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint,
    executed: bool
  }
)

;; NFT Definition for Characters
(define-non-fungible-token character-nft uint)

;; Public Functions

;; Character Management
(define-public (create-character (name (string-ascii 50)))
  (let (
    (character-id (var-get next-character-id))
    (current-block block-height)
  )
    (try! (nft-mint? character-nft character-id tx-sender))
    (map-set characters
      { character-id: character-id }
      {
        owner: tx-sender,
        name: name,
        level: u1,
        experience: u0,
        created-at: current-block,
        last-active: current-block,
        total-games-played: u0,
        cross-chain-hash: 0x00000000000000000000000000000000000000000000000000000000000000
      }
    )
    (var-set next-character-id (+ character-id u1))
    (mint-forge-tokens tx-sender u100) ;; Welcome bonus
    (ok character-id)
  )
)

(define-public (evolve-character (character-id uint))
  (let (
    (character (unwrap! (map-get? characters { character-id: character-id }) err-character-not-found))
    (current-level (get level character))
    (current-exp (get experience character))
    (exp-required (* current-level u1000))
  )
    (asserts! (is-eq (get owner character) tx-sender) err-not-token-owner)
    (asserts! (>= current-exp exp-required) (err u108))
    
    (map-set characters
      { character-id: character-id }
      (merge character {
        level: (+ current-level u1),
        experience: (- current-exp exp-required),
        last-active: block-height
      })
    )
    (mint-forge-tokens tx-sender (* current-level u50))
    (ok (+ current-level u1))
  )
)

;; Trait System
(define-public (create-trait (trait-name (string-ascii 50)) (trait-category (string-ascii 30)) (base-value uint) (max-evolution uint))
  (let (
    (trait-id (var-get next-trait-id))
  )
    (map-set trait-definitions
      { trait-id: trait-id }
      {
        trait-name: trait-name,
        trait-category: trait-category,
        base-value: base-value,
        max-evolution: max-evolution,
        creator: tx-sender,
        creation-block: block-height
      }
    )
    (var-set next-trait-id (+ trait-id u1))
    (mint-forge-tokens tx-sender u25) ;; Creator reward
    (ok trait-id)
  )
)

(define-public (assign-trait-to-character (character-id uint) (trait-id uint) (trait-type (string-ascii 30)) (rarity-tier uint))
  (let (
    (character (unwrap! (map-get? characters { character-id: character-id }) err-character-not-found))
    (trait-def (unwrap! (map-get? trait-definitions { trait-id: trait-id }) err-trait-not-found))
  )
    (asserts! (is-eq (get owner character) tx-sender) err-not-token-owner)
    (asserts! (<= rarity-tier u5) err-invalid-trait-value)
    
    (map-set character-traits
      { character-id: character-id, trait-id: trait-id }
      {
        trait-type: trait-type,
        trait-value: (get base-value trait-def),
        rarity-tier: rarity-tier,
        evolution-level: u0,
        unlock-requirements: ""
      }
    )
    (ok true)
  )
)

(define-public (evolve-trait (character-id uint) (trait-id uint) (forge-cost uint))
  (let (
    (character (unwrap! (map-get? characters { character-id: character-id }) err-character-not-found))
    (current-trait (unwrap! (map-get? character-traits { character-id: character-id, trait-id: trait-id }) err-trait-not-found))
    (trait-def (unwrap! (map-get? trait-definitions { trait-id: trait-id }) err-trait-not-found))
    (current-evolution (get evolution-level current-trait))
  )
    (asserts! (is-eq (get owner character) tx-sender) err-not-token-owner)
    (asserts! (< current-evolution (get max-evolution trait-def)) (err u109))
    (try! (burn-forge-tokens tx-sender forge-cost))
    
    (map-set character-traits
      { character-id: character-id, trait-id: trait-id }
      (merge current-trait {
        evolution-level: (+ current-evolution u1),
        trait-value: (+ (get trait-value current-trait) u10)
      })
    )
    (ok (+ current-evolution u1))
  )
)

;; Game Integration
(define-public (register-game (game-id (string-ascii 50)) (name (string-ascii 100)) (integration-fee uint))
  (begin
    (map-set registered-games
      { game-id: game-id }
      {
        developer: tx-sender,
        name: name,
        integration-fee: integration-fee,
        active: true,
        total-players: u0
      }
    )
    (ok true)
  )
)

(define-public (record-game-session (character-id uint) (game-id (string-ascii 50)) (experience-gained uint) (playtime uint))
  (let (
    (character (unwrap! (map-get? characters { character-id: character-id }) err-character-not-found))
    (game (unwrap! (map-get? registered-games { game-id: game-id }) err-game-not-registered))
    (current-progress (default-to 
      { achievements: u0, playtime: u0, last-session: u0, game-specific-data: "" }
      (map-get? character-game-progress { character-id: character-id, game-id: game-id })
    ))
  )
    (asserts! (is-eq (get owner character) tx-sender) err-not-token-owner)
    (asserts! (get active game) err-game-not-registered)
    
    ;; Update character experience
    (map-set characters
      { character-id: character-id }
      (merge character {
        experience: (+ (get experience character) experience-gained),
        last-active: block-height,
        total-games-played: (+ (get total-games-played character) u1)
      })
    )
    
    ;; Update game progress
    (map-set character-game-progress
      { character-id: character-id, game-id: game-id }
      (merge current-progress {
        playtime: (+ (get playtime current-progress) playtime),
        last-session: block-height
      })
    )
    
    ;; Reward FORGE tokens based on experience gained
    (mint-forge-tokens tx-sender (/ experience-gained u10))
    (ok true)
  )
)

;; Private Token Functions
(define-private (mint-forge-tokens (recipient principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? forge-balances { holder: recipient }))))
  )
    (map-set forge-balances
      { holder: recipient }
      { balance: (+ current-balance amount) }
    )
    (var-set forge-token-supply (+ (var-get forge-token-supply) amount))
    true
  )
)

;; FORGE Token Functions
(define-public (admin-mint-forge-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (mint-forge-tokens recipient amount)
    (ok true)
  )
)

(define-public (burn-forge-tokens (holder principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? forge-balances { holder: holder }))))
  )
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (map-set forge-balances
      { holder: holder }
      { balance: (- current-balance amount) }
    )
    (var-set forge-token-supply (- (var-get forge-token-supply) amount))
    (ok true)
  )
)

(define-public (transfer-forge-tokens (recipient principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? forge-balances { holder: tx-sender }))))
    (recipient-balance (default-to u0 (get balance (map-get? forge-balances { holder: recipient }))))
  )
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (map-set forge-balances { holder: tx-sender } { balance: (- sender-balance amount) })
    (map-set forge-balances { holder: recipient } { balance: (+ recipient-balance amount) })
    (ok true)
  )
)

;; Cross-Chain Functionality
(define-public (sync-character-state (character-id uint) (cross-chain-hash (buff 32)))
  (let (
    (character (unwrap! (map-get? characters { character-id: character-id }) err-character-not-found))
  )
    (asserts! (is-eq (get owner character) tx-sender) err-not-token-owner)
    (map-set characters
      { character-id: character-id }
      (merge character { cross-chain-hash: cross-chain-hash })
    )
    (ok true)
  )
)

;; Governance Functions
(define-public (submit-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-deadline uint))
  (let (
    (proposal-id (var-get next-proposal-id))
    (holder-balance (default-to u0 (get balance (map-get? forge-balances { holder: tx-sender }))))
  )
    (asserts! (>= holder-balance u1000) (err u110)) ;; Minimum 1000 FORGE to propose
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        votes-for: u0,
        votes-against: u0,
        voting-deadline: voting-deadline,
        executed: false
      }
    )
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Read-Only Functions
(define-read-only (get-character (character-id uint))
  (map-get? characters { character-id: character-id })
)

(define-read-only (get-character-traits (character-id uint) (trait-id uint))
  (map-get? character-traits { character-id: character-id, trait-id: trait-id })
)

(define-read-only (get-trait-definition (trait-id uint))
  (map-get? trait-definitions { trait-id: trait-id })
)

(define-read-only (get-forge-balance (holder principal))
  (default-to u0 (get balance (map-get? forge-balances { holder: holder })))
)

(define-read-only (get-total-forge-supply)
  (var-get forge-token-supply)
)

(define-read-only (get-game-info (game-id (string-ascii 50)))
  (map-get? registered-games { game-id: game-id })
)

(define-read-only (get-character-game-progress (character-id uint) (game-id (string-ascii 50)))
  (map-get? character-game-progress { character-id: character-id, game-id: game-id })
)

(define-read-only (get-character-owner (character-id uint))
  (nft-get-owner? character-nft character-id)
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

;; Admin Functions
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) (err u111)) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (emergency-pause-game (game-id (string-ascii 50)))
  (let (
    (game (unwrap! (map-get? registered-games { game-id: game-id }) err-game-not-registered))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set registered-games
      { game-id: game-id }
      (merge game { active: false })
    )
    (ok true)
  )
)