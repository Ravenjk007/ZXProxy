use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use serde::{Deserialize, Serialize};
use warp::{Filter, reply::Json};

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Metrics {
    pub total_connections: u64,
    pub active_connections: u64,
    pub protocol_stats: HashMap<String, ProtocolStats>,
    pub errors: u64,
    pub success: u64,
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct ProtocolStats {
    pub connections: u64,
    pub bytes_transferred: u64,
    pub avg_latency: f64,
    pub success_rate: f64,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            total_connections: 0,
            active_connections: 0,
            protocol_stats: HashMap::new(),
            errors: 0,
            success: 0,
        }
    }
    
    pub fn record_connection(&mut self, protocol: &str) {
        self.total_connections += 1;
        self.active_connections += 1;
        
        let stats = self.protocol_stats
            .entry(protocol.to_string())
            .or_insert_with(ProtocolStats::default);
        stats.connections += 1;
    }
    
    pub fn record_error(&mut self, protocol: &str) {
        self.errors += 1;
        self.active_connections -= 1;
        
        if let Some(stats) = self.protocol_stats.get_mut(protocol) {
            stats.success_rate = (stats.connections as f64 - self.errors as f64) / stats.connections as f64;
        }
    }
    
    pub fn record_success(&mut self, protocol: &str) {
        self.success += 1;
        self.active_connections -= 1;
        
        if let Some(stats) = self.protocol_stats.get_mut(protocol) {
            stats.success_rate = (stats.connections as f64 - self.errors as f64) / stats.connections as f64;
        }
    }
}

pub async fn start_metrics_server(state: crate::AppState) {
    let state_filter = warp::any().map(move || state.clone());
    
    let metrics_route = warp::path("metrics")
        .and(warp::get())
        .and(state_filter)
        .and_then(get_metrics);
    
    let health_route = warp::path("health")
        .and(warp::get())
        .map(|| warp::reply::json(&serde_json::json!({"status": "ok"})));
    
    let routes = metrics_route.or(health_route);
    
    warp::serve(routes)
        .run(([0, 0, 0, 0], 9090))
        .await;
}

async fn get_metrics(state: crate::AppState) -> Result<Json, warp::Rejection> {
    let metrics = state.metrics.read().await;
    Ok(warp::reply::json(&*metrics))
}
