// Parliament is licensed under the BSD License from the Open Source
// Initiative, http://www.opensource.org/licenses/bsd-license.php
//
// Copyright (c) 2001-2009, BBN Technologies, Inc.
// All rights reserved.

package com.bbn.parliament.kb_graph.modify;

import org.apache.jena.sparql.core.DatasetGraph;
import org.apache.jena.sparql.modify.UpdateEngine;
import org.apache.jena.sparql.modify.UpdateEngineBase;
import org.apache.jena.sparql.modify.UpdateEngineFactory;
import org.apache.jena.sparql.modify.UpdateEngineRegistry;
import org.apache.jena.sparql.modify.UpdateEngineWorker;
import org.apache.jena.sparql.modify.UpdateSink;
import org.apache.jena.sparql.modify.UpdateVisitorSink;
import org.apache.jena.sparql.modify.request.UpdateVisitor;
import org.apache.jena.sparql.util.Context;

import com.bbn.parliament.kb_graph.KbGraphStore;

/** @author sallen */
public class KbUpdateEngine extends UpdateEngineBase {
	// Jena 6: UpdateEngineFactory.create no longer takes a Binding; the input
	// binding is applied at update-exec time instead. UpdateEngineBase's
	// constructor and inputBinding field were removed as well.
	private static UpdateEngineFactory factory = new UpdateEngineFactory() {
		@Override
		public boolean accept(DatasetGraph datasetGraph, Context context) {
			return (datasetGraph instanceof KbGraphStore);
		}

		@Override
		public UpdateEngine create(DatasetGraph datasetGraph, Context context) {
			return new KbUpdateEngine((KbGraphStore) datasetGraph, context);
		}
	};

	private UpdateSink updateSink;

	public static UpdateEngineFactory getFactory() {
		return factory;
	}

	public static void register() {
		UpdateEngineRegistry.get().add(getFactory());
	}

	public KbUpdateEngine(KbGraphStore datasetGraph, Context context) {
		super(datasetGraph, context);
		updateSink = null;
	}

	@Override
	public void startRequest() {
	}

	@Override
	public void finishRequest() {
	}

	/**
	 * Returns the {@link UpdateSink}.  In this implementation, this is done by
	 * with an {@link UpdateVisitor} which will visit each update operation
	 * and send the operation to the associated {@link UpdateEngineWorker}.
	 */
	@Override
	public UpdateSink getUpdateSink() {
		if (updateSink == null) {
			var worker = new KbUpdateEngineWorker((KbGraphStore) datasetGraph, context);
			updateSink = new UpdateVisitorSink(worker, null, null);
		}
		return updateSink;
	}
}
