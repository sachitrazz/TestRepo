//! Parses and validates each policy file given on the command line.
fn main() {
    for p in std::env::args().skip(1) {
        let cfg = vfsd_filter::filter::config::FilterConfig::from_file(std::path::Path::new(&p))
            .unwrap_or_else(|e| panic!("{p}: {e}"));
        cfg.validate().unwrap_or_else(|e| panic!("{p}: {e}"));
        println!("{p}: ok (level {:?}, absolute {}, dotdot {}, chmod {})", cfg.audit.level,
            cfg.symlink.allow_absolute_targets, cfg.symlink.allow_dotdot_targets,
            cfg.operations.setattr.allow_chmod);
    }
}
