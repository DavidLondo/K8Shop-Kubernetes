import { PropsWithChildren } from "react";

type ServiceCardProps = PropsWithChildren<{
  title: string;
  description: string;
  endpoint: string;
  cta: {
    label: string;
    onClick: () => void;
    loading?: boolean;
    disabled?: boolean;
  };
}>;

export function ServiceCard({ title, description, endpoint, cta, children }: ServiceCardProps) {
  return (
    <section className="card">
      <header className="card-header">
        <div>
          <h2>{title}</h2>
          <p>{description}</p>
        </div>
        <div className="card-actions">
          {endpoint ? <span className="endpoint">{endpoint}</span> : <span className="endpoint missing">Endpoint no definido</span>}
          <button
            type="button"
            className="primary"
            onClick={cta.onClick}
            disabled={cta.loading || cta.disabled || !endpoint}
          >
            {cta.loading ? "Cargando..." : cta.label}
          </button>
        </div>
      </header>
      <div className="card-body">{children}</div>
    </section>
  );
}
