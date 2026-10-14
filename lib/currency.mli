(** Currencies with their minor-unit exponent.

    A currency is a [code] (["EUR"], ["BTC"], ["USDC"]) and, for tokens that exist on more
    than one chain, a [network] tag (["polygon"]). Its text form is the code alone, or
    [code ^ "@" ^ network]: ["EUR"], ["USDC@polygon"]. Two currencies are equal when their
    text forms are equal; USDC on Ethereum and USDC on Polygon are different currencies.

    Every currency lives in a process-wide registry. ISO 4217 fiat currencies and the
    common crypto assets are registered when the library is linked; others are added with
    [register]. Parsing and deserialization look the code up in the registry, so the
    exponent of a currency can never disagree with the one an amount was written with.

    The registry is safe to read and write from several domains and threads: lookups read
    an immutable snapshot without locking, and [register] publishes a new snapshot
    atomically. The recommended discipline is still to register every currency at startup
    and then call [freeze], so that the set of currencies cannot change while data is
    being read. *)

open! Core

(** Whether a currency is a national (ISO 4217) currency or a crypto asset. *)
module Kind : sig
  type t =
    | Fiat
    | Crypto
  [@@deriving sexp, compare, equal, enumerate]
end

(** A registered currency. Sexp and JSON use the text form (["USDC@polygon"]); reading an
    unregistered currency raises. *)
type t [@@deriving sexp, compare, equal, hash, yojson]

include Comparable.S with type t := t
include Hashable.S with type t := t

(** ["USDC"]. *)
val code : t -> string

(** [Some "polygon"] for ["USDC@polygon"]. *)
val network : t -> string option

(** Number of decimal digits in one major unit: 2 for EUR, 8 for BTC, 18 for ETH. *)
val exponent : t -> int

(** [Fiat] or [Crypto]. *)
val kind : t -> Kind.t

(** ["EUR"], ["USDC@polygon"]. *)
val to_string : t -> string

(** Looks up a registered currency by its text form. *)
val of_string_or_error : string -> t Or_error.t

(** Raises on an unknown currency. *)
val of_string : string -> t

(** [register ~code ?network ~exponent ~kind ()] adds a currency to the registry, or
    returns the existing one when an identical registration exists. Fails on a malformed
    code or network, on an exponent outside [0, 36], on a fiat currency with a network or
    a code that is not three letters, on a clash with a different registration, and on a
    new currency after [freeze]. *)
val register
  :  code:string
  -> ?network:string
  -> exponent:int
  -> kind:Kind.t
  -> unit
  -> t Or_error.t

(** Every registered currency, sorted by text form. *)
val all : unit -> t list

(** [freeze ()] stops the registry from growing: after it, [register] of a new currency
    returns an error, while [register] of an identical, already registered currency still
    returns it (so modules that register at initialisation keep working). There is no
    [unfreeze]. Idempotent. *)
val freeze : unit -> unit

(** Whether [freeze] has been called. *)
val is_frozen : unit -> bool

(** {2 Built-in currencies}

    All 40 built-in fiat currencies are also reachable with [of_string]; these are the
    ones used most often. *)

(** Euro, 2 digits. *)
val eur : t

(** US dollar, 2 digits. *)
val usd : t

(** Pound sterling, 2 digits. *)
val gbp : t

(** Swiss franc, 2 digits. *)
val chf : t

(** Japanese yen, 0 digits. *)
val jpy : t

(** Bitcoin on chain, 8 digits (satoshis). *)
val btc : t

(** Bitcoin on Lightning, with an exponent of 11: Lightning amounts are counted in
    millisatoshis. *)
val btc_lightning : t

(** Ether, 18 digits (wei). *)
val eth : t

(** USDC without a network tag, 6 digits: held off-chain, e.g. at an exchange. *)
val usdc : t

(** USDT without a network tag, 6 digits. *)
val usdt : t

(** [USDC@ethereum], 6 digits. *)
val usdc_ethereum : t

(** [USDC@polygon], 6 digits. *)
val usdc_polygon : t

(** [USDC@solana], 6 digits. *)
val usdc_solana : t

(** [USDT@ethereum], 6 digits. *)
val usdt_ethereum : t

(** [USDT@tron], 6 digits. *)
val usdt_tron : t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    (** Serialized as the text form; reading an unregistered currency fails. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
