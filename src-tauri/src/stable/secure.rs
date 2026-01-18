use crate::stable::utils::{run_shell, shell_escape};
use anyhow::Result;

pub fn run(domain: &str) -> Result<()> {
    let escaped_domain = shell_escape(domain);
    let status = run_shell(
        std::path::Path::new("."),
        &format!("mkcert '{}'", escaped_domain),
    )?;

    if !status.success() {
        anyhow::bail!("Failed to generate certificate for {}", domain);
    }

    Ok(())
}
