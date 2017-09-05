/*
 * Copyright 2017 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.oddgen.sqldev.plugin.templates

import java.io.File
import java.sql.Connection
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.List
import org.oddgen.sqldev.generators.OddgenGenerator2
import org.oddgen.sqldev.generators.model.Node

class NewXtendGenerator implements OddgenGenerator2 {

	public static val OUTPUT_DIR = "Output directory"
	public static val PACKAGE_NAME = "Package name"
	public static val CLASS_NAME = "Class name"

	override getName(Connection conn) {
		return "Xtend generator"
	}

	override getDescription(Connection conn) {
		return "Generate a Xtend oddgen plugin"
	}

	override getFolders(Connection conn) {
		return #["Templates"]
	}

	override getHelp(Connection conn) {
		return "<p>not yet available</p>"
	}

	override getNodes(Connection conn, String parentNodeId) {
		val params = new LinkedHashMap<String, String>()
		params.put(OUTPUT_DIR, '''«System.getProperty("user.home")»«File.separator»oddgen«File.separator»custom«File.separator»plugin''')
		params.put(PACKAGE_NAME, "NewGenerator")
		params.put(CLASS_NAME, "org.oddgen.custom.plugin")
		val node = new Node
		node.id = "new"
		node.params = params
		node.leaf = true
		node.generatable = true
		return #[node]
	}

	override getLov(Connection conn, LinkedHashMap<String, String> params, List<Node> nodes) {
		return new HashMap<String, List<String>>
	}

	override getParamStates(Connection conn, LinkedHashMap<String, String> params, List<Node> nodes) {
		return new HashMap<String, Boolean>
	}

	override generateProlog(Connection conn, List<Node> nodes) {
		return ""
	}

	override generateSeparator(Connection conn) {
		return ""
	}

	override generateEpilog(Connection conn, List<Node> nodes) {
		return ""
	}

	override generate(Connection conn, Node node) {
		return '''
			The plugin has been generated in the directory «node.params.get(OUTPUT_DIR)».
			
			To build the plugin:
			
			1. cd «node.params.get(OUTPUT_DIR)»
			2. mvn clean package
			
			To install the plugin:
			
			1. copy the ... into ...
			2. Restart SQL Developer
		'''
	}

}
