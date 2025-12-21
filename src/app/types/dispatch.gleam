import app/types/service.{type ServiceDescription}
import app/types/service_provider.{type ServiceProviderMessage}
import gleam/erlang/process.{type Name}

/// Information needed to dispatch to a specific service provider
/// The dispatcher holds a dictionary of these values called the service dictionary
/// The service dictionary maps the fully qualified service name to DispatchInfo
pub type DispatchInfo {
  DispatchInfo(
    process_name: Name(ServiceProviderMessage),
    description: ServiceDescription,
  )
}
