# vfsd-filter Kata evaluation

Reproduces the Kata Containers measurements of the FilteredFs paper on a
GitHub hosted runner with KVM.

* `vfsd-filter-0.2.0.tar.gz`: the archived decorator source evaluated in the
  paper (SHA-256 2394c8277a10cc92d7cee5247c8bd6c567da3c74c18bbcfdd4212e48c039657e).
* `daemon/`: virtiofsd v1.14.0 `main` with one change: when
  `VFSD_FILTER_CONFIG` names a policy file, the passthrough backend is wrapped
  in `FilteredFs`. Without the variable it is plain virtiofsd v1.14.0, which is
  the baseline.
* `ci/`: Kata install, shim registration, workloads and the evaluation script.
* `.github/workflows/kata-eval.yml`: runs everything and pushes raw results to
  the `kata-eval-results` branch.
