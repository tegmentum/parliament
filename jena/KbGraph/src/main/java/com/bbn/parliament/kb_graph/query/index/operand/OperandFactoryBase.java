package com.bbn.parliament.kb_graph.query.index.operand;

import java.util.ArrayList;
import java.util.List;

import org.apache.jena.graph.Node;
import org.apache.jena.graph.NodeFactory;
import org.apache.jena.graph.Triple;
import org.apache.jena.sparql.core.BasicPattern;
import org.apache.jena.vocabulary.RDF;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.bbn.parliament.kb_graph.index.QueryableIndex;
import com.bbn.parliament.kb_graph.index.Record;

public abstract class OperandFactoryBase<T> implements OperandFactory<T> {
	private static Logger log = LoggerFactory.getLogger(OperandFactoryBase.class);

	// Jena 6: Triple.subjectMatches/predicateMatches were removed; callers pass
	// concrete nodes, so plain .equals gives the same result.
	protected static BasicPattern getTriplesWithSubject(Node node,
		BasicPattern pattern) {
		BasicPattern p = new BasicPattern();
		for (Triple t : pattern) {
			if (t.getSubject().equals(node)) {
				p.add(t);
			}
		}
		return p;
	}

	protected static List<String> getTypes(BasicPattern pattern) {
		List<String> types = new ArrayList<>();
		Node type = RDF.type.asNode();
		for (Triple t : pattern) {
			if (t.getPredicate().equals(type)) {
				types.add(t.getObject().getURI());
			}
		}
		return types;
	}

	protected static List<Triple> getTriplesWithPredicate(BasicPattern pattern, Node predicate) {
		List<Triple> types = new ArrayList<>();
		for (Triple t : pattern) {
			if (t.getPredicate().equals(predicate)) {
				types.add(t);
			}
		}
		return types;
	}

	protected static void addTypeTriple(String type, Node rootNode, List<Triple> triples) {
		triples.add(Triple.create(rootNode, RDF.type.asNode(), NodeFactory.createURI(type)));
	}

	protected QueryableIndex<T> index;

	public OperandFactoryBase() {
	}

	public QueryableIndex<T> getIndex() {
		return index;
	}

	/** {@inheritDoc} */
	@Override
	public void setIndex(QueryableIndex<T> index) {
		this.index = index;
	}

	protected T findRepresentation(Node node) {
		if (null == getIndex()) {
			log.warn("getIndex() returned null, i.e., index has not yet been set on OperandFactoryBase");
			return null;
		}

		// check cache first (for things like floating extents)
		T extent = getIndex().getQueryCache().get(node);
		if (null != extent) {
			log.trace("Found extent '{}' for node '{}' in the query cache", extent, node);
			return extent;
		}

		Record<T> record = getIndex().find(node);
		if (null == record) {
			log.trace("Unable to find an extent for node '{}' in the index", node);
			return null;
		}
		extent = record.getValue();
		log.trace("Found extent '{}' for node '{}' in the index", extent, node);

		return extent;
	}
}
