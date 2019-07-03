Require Import bedrock2.Syntax bedrock2.StringNamesSyntax bedrock2.BasicCSyntax.
Require Import bedrock2.NotationsCustomEntry coqutil.Z.HexNotation.
Require Import bedrock2.Examples.SPI.

Import BinInt String List.ListNotations.
Local Open Scope Z_scope. Local Open Scope string_scope. Local Open Scope list_scope.
Local Existing Instance BasicCSyntax.StringNames_params.
Local Coercion literal (z : Z) : expr := expr.literal z.
Local Coercion var (x : String.string) : expr := expr.var x.
Local Coercion name_of_func (f : function) := fst f.

Local Notation MMIOWRITE := "MMIOWRITE".
Local Notation MMIOREAD := "MMIOREAD".

Definition lan9250_readword : function :=
  let addr : varname := "addr" in
  let ret : varname := "ret" in
  let err : varname := "err" in
  let SPI_CSMODE_ADDR := "SPI_CSMODE_ADDR" in
  ("lan9250_readword", ((addr::nil), (ret::err::nil), bedrock_func_body:(
    SPI_CSMODE_ADDR = (constr:(Ox"10024018"));
    io! ret = MMIOREAD(SPI_CSMODE_ADDR);
    ret = (ret | constr:(2));
    output! MMIOWRITE(SPI_CSMODE_ADDR, ret);

    (* manually register-allocated, apologies for variable reuse *)
    unpack! ret, err = spi_xchg(constr:(Ox"0b"));        require !err; (* FASTREAD *)
    unpack! ret, err = spi_xchg(addr >> constr:(8));     require !err;
    unpack! ret, err = spi_xchg(addr & constr:(Ox"ff")); require !err;
    unpack! ret, err = spi_xchg(err);                    require !err; (* dummy *)

    unpack! ret, err = spi_xchg(err);                    require !err; (* read *)
    unpack! addr, err = spi_xchg(err);                   require !err; (* read *)
    ret = (ret | (addr << constr:(8)));
    unpack! addr, err = spi_xchg(err);                   require !err; (* read *)
    ret = (ret | (addr << constr:(16)));
    unpack! addr, err = spi_xchg(err);                   require !err; (* read *)
    ret = (ret | (addr << constr:(24)));

    io! addr = MMIOREAD(SPI_CSMODE_ADDR);
    addr = (addr & constr:(Z.lnot 2));
    output! MMIOWRITE(SPI_CSMODE_ADDR, addr)
  ))).

Definition lan9250_writeword : function :=
  let addr : varname := "addr" in
  let data : varname := "data" in
  let Oxff : varname := "Oxff" in
  let eight : varname := "eight" in
  let ret : varname := "ret" in
  let err : varname := "err" in
  let SPI_CSMODE_ADDR := "SPI_CSMODE_ADDR" in
  ("lan9250_writeword", ((addr::data::nil), (err::nil), bedrock_func_body:(
    SPI_CSMODE_ADDR = (constr:(Ox"10024018"));
    io! ret = MMIOREAD(SPI_CSMODE_ADDR);
    ret = (ret | constr:(2));
    output! MMIOWRITE(SPI_CSMODE_ADDR, ret);

    (* manually register-allocated, apologies for variable reuse *)
    Oxff = (constr:(Ox"ff"));
    eight = (constr:(8));
    unpack! ret, err = spi_xchg(constr:(Ox"02")); require !err; (* FASTREAD *)
    unpack! ret, err = spi_xchg(addr >> eight);   require !err;
    unpack! ret, err = spi_xchg(addr & Oxff);     require !err;

    unpack! ret, err = spi_xchg(data & Oxff);     require !err; (* write *)
    data = (data >> eight);
    unpack! ret, err = spi_xchg(data & Oxff);     require !err; (* write *)
    data = (data >> eight);
    unpack! ret, err = spi_xchg(data & Oxff);     require !err; (* write *)
    data = (data >> eight);
    unpack! ret, err = spi_xchg(data);     require !err; (* write *)

    io! addr = MMIOREAD(SPI_CSMODE_ADDR);
    addr = (addr & constr:(Z.lnot 2));
    output! MMIOWRITE(SPI_CSMODE_ADDR, addr)
  ))).

Definition MAC_CSR_DATA : Z := Ox"0A8".
Definition MAC_CSR_CMD : Z := Ox"0A4".
Definition BYTE_TEST : Z := Ox"64".

Definition lan9250_mac_write : function :=
  let addr : varname := "addr" in
  let data : varname := "data" in
  let err : varname := "err" in
  ("lan9250_mac_write", ((addr::data::nil), (err::nil), bedrock_func_body:(
    unpack! err = lan9250_writeword(MAC_CSR_DATA, data);
    require !err;
	  unpack! err = lan9250_writeword(MAC_CSR_CMD, constr:(Z.shiftl 1 31)|addr);
    require !err;
	  unpack! data, err = lan9250_readword(BYTE_TEST)
	  (* while (lan9250_readword(0xA4) >> 31) { } // Wait until BUSY (= MAX_CSR_CMD >> 31) goes low *)
  ))).

Definition HW_CFG : Z := Ox"074".

Definition lan9250_wait_for_boot : function :=
  let err : varname := "err" in
  let i : varname := "i" in
  let byteorder : varname := "byteorder" in
  ("lan9250_wait_for_boot", (nil, (err::nil), bedrock_func_body:(
  err = (constr:(0));
  byteorder = (constr:(0));
  i = (lightbulb_spec.patience); while (i) { i = (i - constr:(1));
	  unpack! err, byteorder = lan9250_readword(constr:(Ox"64"));
    if err { i = (i^i) };
    if (byteorder == constr:(Ox"87654321")) { i = (i^i) }
  }
  ))).

Definition lan9250_init : function :=
  let hw_cfg : varname := "hw_cfg" in
  let err : varname := "err" in
  ("lan9250_init", (nil, (err::nil), bedrock_func_body:(
	  lan9250_wait_for_boot();
	  unpack! hw_cfg, err = lan9250_readword(HW_CFG);
    require !err;
    hw_cfg = (hw_cfg | constr:(Z.shiftl 1 20)); (* mustbeone *)
    hw_cfg = (hw_cfg & constr:(Z.lnot (Z.shiftl 1 21))); (* mustbezero *)
    unpack! err = lan9250_writeword(HW_CFG, hw_cfg);
    require !err;

    (* 20: full duplex; 18: promiscuous; 2, 3: TXEN/RXEN *)
  	unpack! err = lan9250_mac_write(constr:(1), constr:(Z.lor (Z.shiftl 1 20) (Z.lor (Z.shiftl 1 18) (Z.lor (Z.shiftl 1 3) (Z.shiftl 1 2)))));
    require !err;
	  unpack! err = lan9250_writeword(constr:(Ox"070"), constr:(Z.lor (Z.shiftl 1 2) (Z.shiftl 1 1)))
  ))).

Require Import bedrock2.ProgramLogic.
Require Import bedrock2.FE310CSemantics.
Require Import coqutil.Word.Interface.
Require Import Coq.Lists.List. Import ListNotations.
Require Import bedrock2.TracePredicate. Import TracePredicateNotations.
Require bedrock2.Examples.lightbulb_spec.

Import coqutil.Map.Interface.

Instance spec_of_lan9250_readword : ProgramLogic.spec_of "lan9250_readword" := fun functions => forall t m a,
  (Ox"0" <= Word.Interface.word.unsigned a < Ox"400") ->
  WeakestPrecondition.call functions "lan9250_readword" t m [a] (fun T M RETS =>
    M = m /\
    exists ret err, RETS = [ret; err] /\
    exists iol, T = iol ++ t /\
    exists ioh, mmio_trace_abstraction_relation ioh iol /\ Logic.or
      (word.unsigned err <> 0 /\ (any +++ lightbulb_spec.spi_timeout _) ioh)
      (word.unsigned err = 0 /\ lightbulb_spec.lan9250_fastread4 _ _ a ret ioh)).

From coqutil Require Import letexists.
Local Ltac split_if :=
  lazymatch goal with
    |- WeakestPrecondition.cmd _ ?c _ _ _ ?post =>
    let c := eval hnf in c in
        lazymatch c with
        | cmd.cond _ _ _ => letexists; split; [solve[repeat straightline]|split]
        end
  end.

Lemma TracePredicate__any_app_more : forall {T} P (x y : list T), (any +++ P) x -> (any +++ P) (x ++ y).
Proof.
  intros.
  cbv [any] in *.
  destruct H as (?&?&?&?&?); subst.
  rewrite <-app_assoc.
  eapply concat_app; eauto.
Qed.

From coqutil Require Import Z.div_mod_to_equations.
Lemma lan9250_readword_ok : program_logic_goal_for_function! lan9250_readword.
Proof.
  Time repeat straightline.

  repeat match goal with
    | H :  _ /\ _ \/ ?Y /\ _, G : not ?X |- _ =>
        constr_eq X Y; let Z := fresh in destruct H as [|[Z ?]]; [|case (G Z)]
    | H :  not ?Y /\ _ \/ _ /\ _, G : ?X |- _ =>
        constr_eq X Y; let Z := fresh in destruct H as [[Z ?]|]; [case (Z G)|]
    | _ => progress cbv [MMIOREAD MMIOWRITE]
    | _ => progress cbv [SPI_CSMODE_ADDR]
    | |- _ /\ _ => split
    | |- context G[string_dec ?x ?x] =>
        let e := eval cbv in (string_dec x x) in
        let goal := context G [e] in
        change goal
    | |- context G[string_dec ?x ?y] =>
        unshelve erewrite (_ : string_dec x y = right _); [ | exact eq_refl | ]
    | _ => straightline_cleanup
    | |- WeakestPrecondition.cmd _ (cmd.interact _ _ _) _ _ _ _ => eapply WeakestPreconditionProperties.interact_nomem
    | |- Semantics.ext_spec _ _ _ _ _ => progress cbn [parameters Semantics.ext_spec]
    | |- Ox _ <= word.unsigned (word.of_Z ?x) < Ox _ \/ _ => left; clear; cbv; clear; intuition congruence
    | |- _ \/ Ox _ <= word.unsigned (word.of_Z ?x) < Ox _ => right; clear; cbv; clear; intuition congruence
    | H: ?x = 0 |-  _ => rewrite H
    | |- ?F ?a ?b ?c =>
        match F with WeakestPrecondition.get => idtac end;
        let f := (eval cbv beta delta [WeakestPrecondition.get] in F) in
        change (f a b c); cbv beta
    | _ => straightline
    | _ => straightline_call
    | _ => split_if
  end.
  all: try (eexists _, _; split; trivial).
  all: try (exact eq_refl).
  all: auto.

  all : try (
    repeat match goal with x := _ ++ _ |- _ => subst x end;
    eexists; split;
    [ repeat match goal with
      |- context G [cons ?a ?b] =>
        assert_fails (idtac; match b with nil => idtac end);
        let goal := context G [(app (cons a nil) b)] in
        change goal
      end;
    rewrite !app_assoc;
    repeat eapply (fun A => f_equal2 (@List.app A)); eauto |]).

  all : try (
    eexists; split; [
    repeat (eassumption || eapply Forall2_app || eapply Forall2_nil || eapply Forall2_cons) |]).
  all : try ((left + right); eexists _, _; split; exact eq_refl).


  all : try (left; split; [eassumption|]).
  all : repeat rewrite <-app_assoc.

  all : eauto using TracePredicate__any_app_more.

  { rewrite Properties.word.unsigned_sru_nowrap by exact eq_refl.
    1:change (word.unsigned (word.of_Z 8)) with 8.
    rewrite Z.shiftr_div_pow2 by Omega.omega.
    clear -H8.
    change (Ox "400") with (4*256) in *.
    Z.div_mod_to_equations. Lia.lia. }
  { rewrite Properties.word.unsigned_and_nowrap.
    change (word.unsigned (word.of_Z 255)) with (Z.ones 8).
    rewrite Z.land_ones by Omega.omega.
    Z.div_mod_to_equations. Lia.lia. }

  right.
  eexists; eauto.
  eexists _, _,  _, _, _, _.

  cbv [
  lightbulb_spec.lan9250_fastread4
  lightbulb_spec.spi_begin
  lightbulb_spec.spi_xchg_mute
  lightbulb_spec.spi_xchg_dummy
  lightbulb_spec.spi_xchg_deaf
  lightbulb_spec.spi_end
  one
  existsl
  ].

  cbv [concat].
  repeat match goal with
    | |- _ /\ _ => eexists
    | |- exists _, _ => eexists
    | |- ?e = _ => is_evar e; exact eq_refl
    | |- _ = ?e => is_evar e; exact eq_refl
  end.

  1 : rewrite <-app_assoc.
  1 : exact eq_refl.
  all : try eassumption.
  1,2:
    repeat match goal with
    | _ => rewrite word.of_Z_unsigned
    | _ => rewrite word.unsigned_of_Z
    | _ => cbv [word.wrap]; rewrite Z.mod_small
    | _ => solve [trivial]
    end.
  { rewrite Properties.word.unsigned_sru_nowrap by exact eq_refl.
    1:change (word.unsigned (word.of_Z 8)) with 8.
    rewrite Z.shiftr_div_pow2 by Omega.omega.
    revert dependent a; clear; intros.
    change (Ox "400") with (4*256) in *. change (Ox "0") with 0 in *.
    Z.div_mod_to_equations. Lia.lia. }
  { rewrite Properties.word.unsigned_and_nowrap.
    change (word.unsigned (word.of_Z 255)) with (Z.ones 8).
    rewrite Z.land_ones by Omega.omega.
    Z.div_mod_to_equations. Lia.lia. }
  repeat match goal with x := _ |- _ => subst x end.
  cbv [LittleEndian.combine PrimitivePair.pair._1 PrimitivePair.pair._2].
  repeat rewrite ?Properties.word.unsigned_or_nowrap, <-?Z.lor_assoc by exact eq_refl.
  change (Z.shiftl 0 8) with 0 in *; rewrite Z.lor_0_r.
  rewrite !Z.shiftl_lor, !Z.shiftl_shiftl in * by Lia.lia.
  repeat f_equal.

  (* little-endian word conversion, automatable (bitwise Z and word) *)
  all : try rewrite word.unsigned_slu by exact eq_refl.
  all : match goal with |- context[word.unsigned (width:=?w) ?x] => is_var x; replace (word.unsigned (width:=w) x) with (word.wrap (width:=w) (word.unsigned (width:=w) x)) by eapply Properties.word.wrap_unsigned; set (word.unsigned (width:=w) x) as X; clearbody X end.
  all : try erewrite ?word.unsigned_of_Z.
  all : cbv [word.wrap].
  all : change Semantics.width with 32.
  all : repeat match goal with |- context G [?a mod ?b] => let goal := context G [a] in change goal end.
  all : change (8+8) with 16.
  all : change (8+16) with 24.
  all : clear.
  all : rewrite ?Z.shiftl_mul_pow2 by Lia.lia.
  all : try (Z.div_mod_to_equations; Lia.lia).

  Unshelve. all: intros; exact True.
Qed.
