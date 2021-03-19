(* Copyright (C) 2019, Francois Berenger

   Yamanishi laboratory,
   Department of Bioscience and Bioinformatics,
   Faculty of Computer Science and Systems Engineering,
   Kyushu Institute of Technology,
   680-4 Kawazu, Iizuka, Fukuoka, 820-8502, Japan. *)

open Printf

module L = MyList
module Log = Dolog.Log

let compose f g x =
  f (g x)

module Make (SL: Score_label.SL) = struct

  module ROC = Cpm.MakeROC.Make(SL)

  (* what is the proportion of actives if we keep only molecules
     which score above the given threshold.
     Returns the curve EF = f(score_threshold);
     i.e. a list of (threshold, EF) values.
     Scores must have been normalized. *)
  let actives_portion_plot score_labels =
    (* because thresholds are normalized *)
    let thresholds = L.frange 0.0 `To 1.0 51 in
    let nb_actives = L.filter_count SL.get_label score_labels in
    let nb_decoys = L.filter_count (compose not SL.get_label) score_labels in
    let empty, rev_res =
      L.fold_left (fun (to_process, acc) t ->
          let to_process' =
            L.filter (fun sl -> SL.get_score sl > t) to_process in
          let card_act = L.filter_count SL.get_label to_process' in
          let card_dec = L.filter_count (compose not SL.get_label) to_process' in
          let n = L.length to_process' in
          let ef =
            if card_act = 0 || n = 0 then
              0.0 (* there are no more actives above this threshold:
                     the EF falls down to 0.0 (threshold too high) *)
            else (* regular EF formula *)
              (float card_act) /. (float n) in
          let rem_acts = (float card_act) /. (float nb_actives) in
          let rem_decs = (float card_dec) /. (float nb_decoys) in
          (to_process', (t, ef, rem_acts, rem_decs) :: acc)
        ) (score_labels, []) thresholds in
    assert(empty = []);
    (nb_actives, nb_decoys, L.rev rev_res)

  let evaluate_performance ?noplot:(noplot = false)
      top_n maybe_curve_fn scores_fn score_labels =
    let for_auc = match top_n with
      | None -> score_labels
      | Some n ->
        let topn = L.take n score_labels in
        assert(L.length topn = n);
        topn in
    (* save ROC curve *)
    MyList.to_file scores_fn (fun sl ->
        let score = SL.get_score sl in
        let label = SL.get_label sl in
        let name = SL.get_name sl in
        sprintf "%f %d %s" score (Utls.int_of_bool label) name
      ) for_auc;
    let auc = ROC.fast_auc for_auc in
    let bedroc = ROC.bedroc_auc for_auc in
    let pr = ROC.pr_auc for_auc in
    (* compute ROC curve *)
    let curve_fn = match maybe_curve_fn with
      | None -> Filename.temp_file "rf_train_" ".roc"
      | Some fn -> fn in
    let pr_curve_fn = Filename.temp_file "rf_train_" ".pr" in
    let roc_curve = ROC.roc_curve for_auc in
    let pr_curve = ROC.pr_curve for_auc in
    MyList.to_file curve_fn (fun (x, y) -> sprintf "%f %f" x y) roc_curve;
    MyList.to_file pr_curve_fn (fun (x, y) -> sprintf "%f %f" x y) pr_curve;
    (* plot ROC curve *)
    let ef_curve_fn = Filename.temp_file "rf_train_" ".ef" in
    let nb_acts, nb_decs, ef_curve = actives_portion_plot for_auc in
    MyList.to_file ef_curve_fn
      (fun (t, ef, ra, rd) -> sprintf "%f %f %f %f" t ef ra rd) ef_curve;
    if not noplot then
      Gnuplot.roc_curve auc bedroc pr
        scores_fn curve_fn pr_curve_fn nb_acts nb_decs ef_curve_fn;
    Log.info "auc: %.3f bedroc: %.3f" auc bedroc

end
