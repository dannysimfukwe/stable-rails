use crate::stable::{start, stop};
use anyhow::Result;

pub fn run(name: &str) -> Result<()> {
    stop::run(name)?;
    start::run(name)?;
    Ok(())
}
