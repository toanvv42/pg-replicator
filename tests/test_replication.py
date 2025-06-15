
#!/usr/bin/env python3
"""
PostgreSQL Logical Replication Test Suite

This module provides comprehensive test cases for both Docker Compose and Kubernetes
setups to ensure PostgreSQL logical replication works correctly.
"""

import os
import sys
import time
import subprocess
import psycopg2
import pytest
from typing import Dict, List, Optional, Tuple
import logging
from dataclasses import dataclass
from contextlib import contextmanager

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class DatabaseConfig:
    """Database connection configuration"""
    host: str
    port: int
    database: str
    username: str
    password: str
    
    def connection_string(self) -> str:
        return f"postgresql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"

class ReplicationTester:
    """Main class for testing PostgreSQL logical replication"""
    
    def __init__(self, source_config: DatabaseConfig, target_config: DatabaseConfig):
        self.source_config = source_config
        self.target_config = target_config
        self.test_data_inserted = False
    
    @contextmanager
    def get_connection(self, config: DatabaseConfig):
        """Context manager for database connections"""
        conn = None
        try:
            conn = psycopg2.connect(
                host=config.host,
                port=config.port,
                database=config.database,
                user=config.username,
                password=config.password
            )
            conn.autocommit = True
            yield conn
        except Exception as e:
            logger.error(f"Database connection error: {e}")
            raise
        finally:
            if conn:
                conn.close()
    
    def wait_for_database(self, config: DatabaseConfig, timeout: int = 60) -> bool:
        """Wait for database to be ready"""
        logger.info(f"Waiting for database at {config.host}:{config.port} to be ready...")
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                # Use pg_isready for health check
                result = subprocess.run([
                    'pg_isready', 
                    '-h', config.host,
                    '-p', str(config.port),
                    '-U', config.username,
                    '-d', config.database
                ], capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0:
                    logger.info(f"Database at {config.host}:{config.port} is ready")
                    return True
                    
            except (subprocess.TimeoutExpired, FileNotFoundError):
                # Fallback to psycopg2 connection test if pg_isready is not available
                try:
                    with self.get_connection(config):
                        logger.info(f"Database at {config.host}:{config.port} is ready")
                        return True
                except:
                    pass
            
            time.sleep(2)
        
        logger.error(f"Database at {config.host}:{config.port} not ready after {timeout}s")
        return False
    
    def test_database_connectivity(self) -> Tuple[bool, bool]:
        """Test connectivity to both source and target databases"""
        logger.info("Testing database connectivity...")
        
        source_ready = self.wait_for_database(self.source_config)
        target_ready = self.wait_for_database(self.target_config)
        
        return source_ready, target_ready
    
    def test_replication_setup(self) -> Dict[str, bool]:
        """Test that replication is properly set up"""
        logger.info("Testing replication setup...")
        results = {}
        
        # Test publication exists on source
        try:
            with self.get_connection(self.source_config) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT COUNT(*) FROM pg_publication WHERE pubname = 'my_publication';")
                    pub_count = cur.fetchone()[0]
                    results['publication_exists'] = pub_count > 0
                    logger.info(f"Publication exists: {results['publication_exists']}")
        except Exception as e:
            logger.error(f"Error checking publication: {e}")
            results['publication_exists'] = False
        
        # Test subscription exists on target
        try:
            with self.get_connection(self.target_config) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT COUNT(*) FROM pg_subscription WHERE subname = 'my_subscription';")
                    sub_count = cur.fetchone()[0]
                    results['subscription_exists'] = sub_count > 0
                    logger.info(f"Subscription exists: {results['subscription_exists']}")
        except Exception as e:
            logger.error(f"Error checking subscription: {e}")
            results['subscription_exists'] = False
        
        # Test replication slot exists on source
        try:
            with self.get_connection(self.source_config) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = 'my_subscription';")
                    slot_count = cur.fetchone()[0]
                    results['replication_slot_exists'] = slot_count > 0
                    logger.info(f"Replication slot exists: {results['replication_slot_exists']}")
        except Exception as e:
            logger.error(f"Error checking replication slot: {e}")
            results['replication_slot_exists'] = False
        
        # Test subscription is enabled and active
        try:
            with self.get_connection(self.target_config) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT subenabled FROM pg_subscription WHERE subname = 'my_subscription';")
                    result = cur.fetchone()
                    results['subscription_enabled'] = result[0] if result else False
                    logger.info(f"Subscription enabled: {results['subscription_enabled']}")
        except Exception as e:
            logger.error(f"Error checking subscription status: {e}")
            results['subscription_enabled'] = False
        
        return results
    
    def test_data_replication(self, timeout: int = 30) -> Dict[str, any]:
        """Test actual data replication"""
        logger.info("Testing data replication...")
        results = {}
        
        # Insert test data on source
        test_timestamp = int(time.time())
        test_email = f"test_{test_timestamp}@example.com"
        test_name = f"Test User {test_timestamp}"
        
        try:
            with self.get_connection(self.source_config) as conn:
                with conn.cursor() as cur:
                    # Insert test user
                    cur.execute(
                        "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id;",
                        (test_name, test_email)
                    )
                    test_user_id = cur.fetchone()[0]
                    
                    # Insert test order
                    cur.execute(
                        "INSERT INTO orders (user_id, product_name, amount) VALUES (%s, %s, %s) RETURNING id;",
                        (test_user_id, f"Test Product {test_timestamp}", 99.99)
                    )
                    test_order_id = cur.fetchone()[0]
                    
                    results['test_data_inserted'] = True
                    results['test_user_id'] = test_user_id
                    results['test_order_id'] = test_order_id
                    logger.info(f"Test data inserted: user_id={test_user_id}, order_id={test_order_id}")
                    
        except Exception as e:
            logger.error(f"Error inserting test data: {e}")
            results['test_data_inserted'] = False
            return results
        
        # Wait for replication
        logger.info(f"Waiting {timeout}s for replication...")
        time.sleep(timeout)
        
        # Verify data on target
        try:
            with self.get_connection(self.target_config) as conn:
                with conn.cursor() as cur:
                    # Check user replication
                    cur.execute("SELECT COUNT(*) FROM users WHERE email = %s;", (test_email,))
                    user_count = cur.fetchone()[0]
                    results['user_replicated'] = user_count > 0
                    
                    # Check order replication
                    cur.execute("SELECT COUNT(*) FROM orders WHERE user_id = %s;", (test_user_id,))
                    order_count = cur.fetchone()[0]
                    results['order_replicated'] = order_count > 0
                    
                    logger.info(f"User replicated: {results['user_replicated']}")
                    logger.info(f"Order replicated: {results['order_replicated']}")
                    
        except Exception as e:
            logger.error(f"Error verifying replicated data: {e}")
            results['user_replicated'] = False
            results['order_replicated'] = False
        
        return results
    
    def test_replication_lag(self) -> Dict[str, any]:
        """Test replication lag and performance"""
        logger.info("Testing replication lag...")
        results = {}
        
        try:
            with self.get_connection(self.source_config) as conn:
                with conn.cursor() as cur:
                    # Get replication statistics
                    cur.execute("""
                        SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
                               pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
                        FROM pg_stat_replication 
                        WHERE application_name = 'my_subscription';
                    """)
                    repl_stats = cur.fetchone()
                    
                    if repl_stats:
                        results['replication_active'] = repl_stats[1] == 'streaming'
                        results['lag_bytes'] = repl_stats[6] if repl_stats[6] else 0
                        results['lag_acceptable'] = results['lag_bytes'] < 1024  # Less than 1KB lag
                        logger.info(f"Replication lag: {results['lag_bytes']} bytes")
                    else:
                        results['replication_active'] = False
                        results['lag_bytes'] = None
                        results['lag_acceptable'] = False
                        
        except Exception as e:
            logger.error(f"Error checking replication lag: {e}")
            results['replication_active'] = False
            results['lag_bytes'] = None
            results['lag_acceptable'] = False
        
        return results
    
    def run_comprehensive_test(self) -> Dict[str, any]:
        """Run all tests and return comprehensive results"""
        logger.info("Starting comprehensive replication test...")
        
        all_results = {}
        
        # Test 1: Database connectivity
        source_ready, target_ready = self.test_database_connectivity()
        all_results['connectivity'] = {
            'source_ready': source_ready,
            'target_ready': target_ready,
            'both_ready': source_ready and target_ready
        }
        
        if not (source_ready and target_ready):
            logger.error("Database connectivity test failed")
            return all_results
        
        # Test 2: Replication setup
        all_results['setup'] = self.test_replication_setup()
        
        setup_ok = all(all_results['setup'].values())
        if not setup_ok:
            logger.error("Replication setup test failed")
            return all_results
        
        # Test 3: Data replication
        all_results['data_replication'] = self.test_data_replication()
        
        # Test 4: Replication lag
        all_results['performance'] = self.test_replication_lag()
        
        # Overall success
        all_results['overall_success'] = (
            all_results['connectivity']['both_ready'] and
            setup_ok and
            all_results['data_replication'].get('user_replicated', False) and
            all_results['data_replication'].get('order_replicated', False) and
            all_results['performance'].get('replication_active', False)
        )
        
        logger.info(f"Comprehensive test completed. Success: {all_results['overall_success']}")
        return all_results

# Docker Compose Test Configuration
def get_docker_compose_config() -> Tuple[DatabaseConfig, DatabaseConfig]:
    """Get database configurations for Docker Compose setup"""
    source_config = DatabaseConfig(
        host='localhost',
        port=5432,
        database='sourcedb',
        username='postgres',
        password='postgres'
    )
    
    target_config = DatabaseConfig(
        host='localhost',
        port=5433,
        database='targetdb',
        username='postgres',
        password='postgres'
    )
    
    return source_config, target_config

# Kubernetes Test Configuration
def get_kubernetes_config() -> Tuple[DatabaseConfig, DatabaseConfig]:
    """Get database configurations for Kubernetes setup"""
    source_config = DatabaseConfig(
        host='postgres-source.database-replication.svc.cluster.local',
        port=5432,
        database='sourcedb',
        username='postgres',
        password='postgres'
    )
    
    target_config = DatabaseConfig(
        host='postgres-target.database-replication.svc.cluster.local',
        port=5432,
        database='targetdb',
        username='postgres',
        password='postgres'
    )
    
    return source_config, target_config

# Pytest Test Cases
class TestDockerCompose:
    """Test cases for Docker Compose setup"""
    
    @pytest.fixture(scope="class")
    def tester(self):
        source_config, target_config = get_docker_compose_config()
        return ReplicationTester(source_config, target_config)
    
    def test_database_connectivity(self, tester):
        """Test database connectivity"""
        source_ready, target_ready = tester.test_database_connectivity()
        assert source_ready, "Source database should be ready"
        assert target_ready, "Target database should be ready"
    
    def test_replication_setup(self, tester):
        """Test replication setup"""
        results = tester.test_replication_setup()
        assert results['publication_exists'], "Publication should exist on source"
        assert results['subscription_exists'], "Subscription should exist on target"
        assert results['replication_slot_exists'], "Replication slot should exist on source"
        assert results['subscription_enabled'], "Subscription should be enabled"
    
    def test_data_replication(self, tester):
        """Test data replication"""
        results = tester.test_data_replication()
        assert results['test_data_inserted'], "Test data should be inserted"
        assert results['user_replicated'], "User data should be replicated"
        assert results['order_replicated'], "Order data should be replicated"
    
    def test_replication_performance(self, tester):
        """Test replication performance"""
        results = tester.test_replication_lag()
        assert results['replication_active'], "Replication should be active"
        assert results['lag_acceptable'], "Replication lag should be acceptable"

class TestKubernetes:
    """Test cases for Kubernetes setup"""
    
    @pytest.fixture(scope="class")
    def tester(self):
        source_config, target_config = get_kubernetes_config()
        return ReplicationTester(source_config, target_config)
    
    def test_database_connectivity(self, tester):
        """Test database connectivity"""
        source_ready, target_ready = tester.test_database_connectivity()
        assert source_ready, "Source database should be ready"
        assert target_ready, "Target database should be ready"
    
    def test_replication_setup(self, tester):
        """Test replication setup"""
        results = tester.test_replication_setup()
        assert results['publication_exists'], "Publication should exist on source"
        assert results['subscription_exists'], "Subscription should exist on target"
        assert results['replication_slot_exists'], "Replication slot should exist on source"
        assert results['subscription_enabled'], "Subscription should be enabled"
    
    def test_data_replication(self, tester):
        """Test data replication"""
        results = tester.test_data_replication()
        assert results['test_data_inserted'], "Test data should be inserted"
        assert results['user_replicated'], "User data should be replicated"
        assert results['order_replicated'], "Order data should be replicated"
    
    def test_replication_performance(self, tester):
        """Test replication performance"""
        results = tester.test_replication_lag()
        assert results['replication_active'], "Replication should be active"
        assert results['lag_acceptable'], "Replication lag should be acceptable"

# CLI Interface
def main():
    """Main CLI interface for running tests"""
    import argparse
    
    parser = argparse.ArgumentParser(description='PostgreSQL Replication Test Suite')
    parser.add_argument('--mode', choices=['docker', 'kubernetes'], required=True,
                       help='Test mode: docker or kubernetes')
    parser.add_argument('--timeout', type=int, default=30,
                       help='Timeout for replication tests (default: 30s)')
    parser.add_argument('--verbose', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Get configuration based on mode
    if args.mode == 'docker':
        source_config, target_config = get_docker_compose_config()
    else:
        source_config, target_config = get_kubernetes_config()
    
    # Run tests
    tester = ReplicationTester(source_config, target_config)
    results = tester.run_comprehensive_test()
    
    # Print results
    print("\n" + "="*50)
    print("POSTGRESQL REPLICATION TEST RESULTS")
    print("="*50)
    
    for category, category_results in results.items():
        if category == 'overall_success':
            continue
            
        print(f"\n{category.upper()}:")
        if isinstance(category_results, dict):
            for test, result in category_results.items():
                status = "PASS" if result else "FAIL"
                print(f"  {test}: {status}")
        else:
            status = "PASS" if category_results else "FAIL"
            print(f"  {status}")
    
    print(f"\nOVERALL: {'PASS' if results.get('overall_success', False) else 'FAIL'}")
    print("="*50)
    
    # Exit with appropriate code
    sys.exit(0 if results.get('overall_success', False) else 1)

if __name__ == '__main__':
    main()