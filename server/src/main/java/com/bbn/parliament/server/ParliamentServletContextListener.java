package com.bbn.parliament.server;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;

public class ParliamentServletContextListener implements ServletContextListener {
	private static final Logger LOG = LoggerFactory.getLogger(ParliamentServletContextListener.class);

	public ParliamentServletContextListener() {
		LOG.info("ParliamentServletContextListener created");
	}

	@Override
	public void contextInitialized(ServletContextEvent sce) {
		LOG.info("contextInitialized");
		// Register tegmentum WebAssembly filter functions (wf:call and
		// friends) into Jena's global FunctionRegistry so SPARQL queries
		// arriving at Parliament's endpoint can call wasm components.
		ai.tegmentum.jena.webfunctions.WebFunctionInit.register();
		LOG.info("Registered tegmentum wf:call function registry entries");
	}

	@Override
	public void contextDestroyed(ServletContextEvent sce) {
		LOG.info("Shutting down parliament servlet");
		ParliamentBridge.getInstance().stop();
	}
}
