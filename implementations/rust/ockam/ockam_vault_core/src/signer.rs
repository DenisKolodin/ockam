use crate::secret::Secret;
use crate::Signature;
use ockam_core::Result;
use ockam_core::{async_trait, compat::boxed::Box};

/// Signing functionality
#[async_trait]
pub trait Signer {
    /// Generate a signature  for given data using given secret key
    async fn sign(&mut self, secret_key: &Secret, data: &[u8]) -> Result<Signature>;
}
