#!/bin/bash
# Master Experiment Runner - Orchestrates the full experimentation pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_DIR="$SCRIPT_DIR/experiments"
ACTIVE_DIR="$EXP_DIR/active"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Phase 1: Create experiments from hypotheses
phase_create() {
    log_step "Phase 1: Creating experiments from hypotheses"
    
    bash "$EXP_DIR/experiment-manager.sh" create-all
    
    local count=$(ls -1 "$ACTIVE_DIR" 2>/dev/null | wc -l)
    
    if [[ $count -eq 0 ]]; then
        log_warning "No experiments created. Check if hypotheses.json exists."
        return 1
    fi
    
    log_success "Created $count experiment(s)"
}

# Phase 2: Generate variants
phase_generate() {
    log_step "Phase 2: Generating variants"
    
    if [[ ! -d "$ACTIVE_DIR" ]] || [[ -z "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        log_error "No experiments found. Run 'create' phase first."
        return 1
    fi
    
    local generated=0
    
    for exp_file in "$ACTIVE_DIR"/*.json; do
        local exp_id=$(jq -r '.id' "$exp_file")
        local status=$(jq -r '.status' "$exp_file")
        
        if [[ "$status" == "created" ]]; then
            echo ""
            log_step "Generating variant for $exp_id"
            
            if bash "$EXP_DIR/variant-generator.sh" generate "$exp_id"; then
                generated=$((generated + 1))
            else
                log_error "Failed to generate variant for $exp_id"
            fi
        fi
    done
    
    if [[ $generated -eq 0 ]]; then
        log_warning "No new variants generated"
    else
        log_success "Generated $generated variant(s)"
    fi
}

# Phase 3: Run shadow tests
phase_test() {
    log_step "Phase 3: Running shadow tests"
    
    local iterations="${1:-10}"
    
    if [[ ! -d "$ACTIVE_DIR" ]] || [[ -z "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        log_error "No experiments found."
        return 1
    fi
    
    local tested=0
    
    for exp_file in "$ACTIVE_DIR"/*.json; do
        local exp_id=$(jq -r '.id' "$exp_file")
        local status=$(jq -r '.status' "$exp_file")
        
        if [[ "$status" == "variant_generated" ]] || [[ "$status" == "created" ]]; then
            echo ""
            log_step "Testing $exp_id with $iterations iterations"
            
            if bash "$EXP_DIR/shadow-runner.sh" run "$exp_id" "$iterations"; then
                tested=$((tested + 1))
            else
                log_error "Failed to test $exp_id"
            fi
        fi
    done
    
    if [[ $tested -eq 0 ]]; then
        log_warning "No experiments tested"
    else
        log_success "Tested $tested experiment(s)"
    fi
}

# Phase 4: Evaluate results
phase_evaluate() {
    log_step "Phase 4: Evaluating results"
    
    if [[ ! -d "$ACTIVE_DIR" ]] || [[ -z "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        log_error "No experiments found."
        return 1
    fi
    
    local evaluated=0
    
    for exp_file in "$ACTIVE_DIR"/*.json; do
        local exp_id=$(jq -r '.id' "$exp_file")
        local status=$(jq -r '.status' "$exp_file")
        
        if [[ "$status" == "completed" ]]; then
            echo ""
            log_step "Evaluating $exp_id"
            
            if bash "$EXP_DIR/stat-evaluator.sh" evaluate "$exp_id"; then
                evaluated=$((evaluated + 1))
            else
                log_error "Failed to evaluate $exp_id"
            fi
        fi
    done
    
    if [[ $evaluated -eq 0 ]]; then
        log_warning "No experiments evaluated"
    else
        log_success "Evaluated $evaluated experiment(s)"
    fi
}

# Phase 5: Deploy winners
phase_deploy() {
    log_step "Phase 5: Deploying winning experiments"
    
    if [[ ! -d "$ACTIVE_DIR" ]] || [[ -z "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        log_error "No experiments found."
        return 1
    fi
    
    local deployed=0
    
    for exp_file in "$ACTIVE_DIR"/*.json; do
        local exp_id=$(jq -r '.id' "$exp_file")
        local result=$(jq -r '.result // "null"' "$exp_file")
        
        if [[ "$result" == "deploy" ]]; then
            echo ""
            log_step "Deploying $exp_id"
            
            if bash "$EXP_DIR/deploy-experiment.sh" deploy "$exp_id"; then
                deployed=$((deployed + 1))
            else
                log_error "Failed to deploy $exp_id"
            fi
        fi
    done
    
    if [[ $deployed -eq 0 ]]; then
        log_warning "No experiments deployed"
    else
        log_success "Deployed $deployed experiment(s)"
    fi
}

# Phase 6: Check probation
phase_rollback() {
    log_step "Phase 6: Checking probation experiments"
    
    bash "$EXP_DIR/rollback.sh" check
}

# Phase 7: Dashboard
phase_dashboard() {
    bash "$EXP_DIR/dashboard.sh"
}

# Run all phases
run_all() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Self-Improvement Experimentation Pipeline"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    local iterations="${1:-10}"
    
    phase_create
    echo ""
    
    phase_generate
    echo ""
    
    phase_test "$iterations"
    echo ""
    
    phase_evaluate
    echo ""
    
    phase_deploy
    echo ""
    
    phase_rollback
    echo ""
    
    log_success "Pipeline complete!"
    echo ""
    
    phase_dashboard
}

# Main command router
case "${1:-dashboard}" in
    create)
        phase_create
        ;;
    generate)
        phase_generate
        ;;
    test)
        phase_test "${2:-10}"
        ;;
    evaluate)
        phase_evaluate
        ;;
    deploy)
        phase_deploy
        ;;
    rollback)
        phase_rollback
        ;;
    dashboard)
        phase_dashboard
        ;;
    all)
        run_all "${2:-10}"
        ;;
    *)
        echo "Usage: $0 {create|generate|test [iterations]|evaluate|deploy|rollback|dashboard|all [iterations]}"
        echo ""
        echo "Phases:"
        echo "  create      - Create experiments from hypotheses"
        echo "  generate    - Generate variants for new experiments"
        echo "  test        - Run shadow tests (default: 10 iterations)"
        echo "  evaluate    - Evaluate completed experiments"
        echo "  deploy      - Deploy winning experiments"
        echo "  rollback    - Check probation and rollback if needed"
        echo "  dashboard   - Show experiment summary"
        echo "  all         - Run full pipeline"
        exit 1
        ;;
esac
