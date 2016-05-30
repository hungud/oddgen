/*
 * Copyright 2015-2016 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
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
package org.oddgen.sqldev.dal.tests

import java.util.LinkedHashMap
import java.util.Properties
import org.junit.AfterClass
import org.junit.Assert
import org.junit.BeforeClass
import org.junit.Test
import org.oddgen.sqldev.dal.DatabaseGeneratorDao
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.datasource.SingleConnectionDataSource

class DatabaseGeneratorTest {

	private static SingleConnectionDataSource dataSource
	private static JdbcTemplate jdbcTemplate

	@Test
	def daoTest() {
		val dao = new DatabaseGeneratorDao(dataSource.connection)
		val dbgens = dao.findAll
		val plsqlView = dbgens.findFirst [
			it.dto.generatorOwner == dataSource.username.toUpperCase && it.dto.generatorName == "PLSQL_VIEW"
		]
		Assert.assertEquals("1:1 View (PL/SQL)", plsqlView.getName(dataSource.connection))
		Assert.assertEquals(
			"Generates a 1:1 view based on an existing table. Optionally generates a simple instead of trigger. The generator is based on plain PL/SQL without a third party template engine.",
			plsqlView.getDescription(dataSource.connection))
		Assert.assertEquals(1, plsqlView.getObjectTypes(dataSource.connection).size)
		Assert.assertEquals("TABLE", plsqlView.getObjectTypes(dataSource.connection).get(0))
		var params = plsqlView.getParams(dataSource.connection, "TABLE", "PLSQL_VIEW")
		Assert.assertEquals(4, params.size)
		Assert.assertEquals("View suffix", params.keySet.get(0))
		Assert.assertEquals("Table suffix to be replaced", params.keySet.get(1))
		Assert.assertEquals("Generate instead-of-trigger?", params.keySet.get(2))
		Assert.assertEquals("Instead-of-trigger suffix", params.keySet.get(3))
		Assert.assertEquals("_V", params.get("View suffix"))
		Assert.assertEquals("_T", params.get("Table suffix to be replaced"))
		Assert.assertEquals("_TRG", params.get("Instead-of-trigger suffix"))
		Assert.assertEquals("Yes", params.get("Generate instead-of-trigger?"))
		var lovs = plsqlView.getLovs(dataSource.connection, "TABLE", "PLSQL_VIEW", params)
		Assert.assertEquals(2, lovs.get("Generate instead-of-trigger?").size)
		Assert.assertEquals("Yes", lovs.get("Generate instead-of-trigger?").get(0))
		Assert.assertEquals("No", lovs.get("Generate instead-of-trigger?").get(1))
		var paramStates = plsqlView.getParamStates(dataSource.connection, "TABLE", "PLSQL_VIEW", params)
		Assert.assertEquals(1, paramStates.size)
		Assert.assertEquals(true, paramStates.get("Instead-of-trigger suffix"))
		Assert.assertFalse(plsqlView.dto.isRefreshable)
	}

	@Test
	def refreshLovTest() {
		val dao = new DatabaseGeneratorDao(dataSource.connection)
		val dbgen = dao.findAll.findFirst[it.dto.generatorName == 'PLSQL_DUMMY']
		Assert.assertTrue(dbgen.dto.isRefreshable)
		var params = dbgen.getParams(dataSource.connection, null, null)
		var lovs = dbgen.getLovs(dataSource.connection, null, null, params)
		Assert.assertEquals(2, lovs.get("With grandchildren?").size)
		Assert.assertEquals("Yes", lovs.get("With grandchildren?").get(0))
		Assert.assertEquals("No", lovs.get("With grandchildren?").get(1))
		params.put('With children?', 'No')
		lovs = dbgen.getLovs(dataSource.connection, null, null, params)
		Assert.assertEquals(1, lovs.get("With grandchildren?").size)
		Assert.assertEquals("No", lovs.get("With grandchildren?").get(0))
	}

	@Test
	def generateTest() {
		val dao = new DatabaseGeneratorDao(dataSource.connection)
		val dbgen = dao.findAll.findFirst[it.dto.generatorName == 'PLSQL_DUMMY']
		val expected = '''
			Object type: TABLE
			Object name: SOME_TABLE
			With children: Yes
			With grandchildren: Yes
		'''
	
		val params = dbgen.getParams(dataSource.connection, null, null)
		params.put("dummy","value")
		val generated = dbgen.generate(dataSource.connection, "TABLE", "SOME_TABLE", params)
		Assert.assertEquals(expected.trim, generated.trim)
	}

	@Test
	def generateHelloWorldTest() {
		val dao = new DatabaseGeneratorDao(dataSource.connection)
		val dbgen = dao.findAll.findFirst [
			it.dto.generatorOwner == dataSource.username.toUpperCase && it.dto.generatorName == 'PLSQL_HELLO_WORLD'
		]
		val expected = '''
			BEGIN
			   sys.dbms_output.put_line('Hello VIEW EMP_V!');
			END;
			/
		'''
		val generated = dbgen.generate(dataSource.connection, "VIEW", "EMP_V", null)
		Assert.assertEquals(expected.trim, generated.trim)
	}

	@Test
	def generateErrorTest() {
		val dao = new DatabaseGeneratorDao(dataSource.connection)
		val dbgen = dao.findAll.findFirst [
			it.dto.generatorOwner == dataSource.username.toUpperCase && it.dto.generatorName == 'PLSQL_HELLO_WORLD'
		]
		dbgen.dto.generatorName = 'NON_EXISTING_PACKAGE'
		val expected = '''
			Failed to generate code for TYPE.NAME via ODDGEN.NON_EXISTING_PACKAGE. Got the following error: ORA-06550: line 4, column 14:
			PLS-00201: identifier 'ODDGEN.NON_EXISTING_PACKAGE' must be declared
			ORA-06550: line 4, column 4:
			PL/SQL: Statement ignored
		'''
		val generated = dbgen.generate(dataSource.connection, "TYPE", "NAME", null)
		Assert.assertEquals(expected.trim, generated?.trim)
	}

	@BeforeClass
	def static setup() {
		// get properties
		val p = new Properties()
		p.load(DatabaseGeneratorTest.getClass().getResourceAsStream(
			"/test.properties"))
		// create dataSource and jdbcTemplate
		dataSource = new SingleConnectionDataSource()
		dataSource.driverClassName = "oracle.jdbc.OracleDriver"
		dataSource.url = '''jdbc:oracle:thin:@«p.getProperty("host")»:«p.getProperty("port")»/«p.getProperty("service")»'''
		dataSource.username = p.getProperty("oddgen_username")
		dataSource.password = p.getProperty("oddgen_password")
		jdbcTemplate = new JdbcTemplate(dataSource)

		// deploy PL/SQL packages 
		createPlsqlHelloWorld
		createPlsqlView
		createPlsqlDummy
	}

	@AfterClass
	def static tearDown() {
		val jdbcTemplate = new JdbcTemplate(dataSource)
		// jdbcTemplate.execute("DROP PACKAGE plsql_hello_world")
		// jdbcTemplate.execute("DROP PACKAGE plsql_view")
		jdbcTemplate.execute("DROP PACKAGE plsql_dummy")
	}

	def static createPlsqlHelloWorld() {
		// create package specification of plsql_hello_world generator
		// copy of oddgen/examples/package/plsql/plsql_hello_world.pks
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE plsql_hello_world IS
			   /*
			   * Copyright 2015-2016 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
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
			
			   /**
			   * oddgen PL/SQL hello world example.
			   *
			   * @headcom
			   */
			
			   /**
			   * Generates the result.
			   *
			   * @param in_object_type object type to process
			   * @param in_object_name object_name of object_type_in to process
			   * @returns generator output
			   */
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2) RETURN CLOB;
			
			END plsql_hello_world;
		''')

		// create package body of plsql_hello_world generator
		// copy of oddgen/examples/package/plsql/plsql_hello_world.pkb
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE BODY plsql_hello_world IS
			   /*
			   * Copyright 2015-2016 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
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
			
			   --
			   -- generate
			   --
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2) RETURN CLOB IS
			      l_result CLOB;
			   BEGIN
			      l_result := 'BEGIN' || chr(10) ||
			                  '   sys.dbms_output.put_line(''Hello ' || in_object_type || ' ' || in_object_name || '!'');' || chr(10) ||
			                  'END;' || chr(10) || 
			                  '/' || chr(10);
			      RETURN l_result;
			   END generate;
			END plsql_hello_world;
		''')
	}

	def static createPlsqlView() {
		// create package specification of plsql_view generator
		// copy of oddgen/examples/package/plsql/plsql_view.pks
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE plsql_view AUTHID CURRENT_USER IS
			   /*
			   * Copyright 2015-2016 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
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
			
			   /** 
			   * oddgen PL/SQL example to generate a 1:1 view based on an existing table.
			   *
			   * @headcom
			   */
			
			   /*
			   * oddgen PL/SQL data types
			   */
			   SUBTYPE string_type IS VARCHAR2(1000 CHAR);
			   SUBTYPE param_type IS VARCHAR2(30 CHAR);
			   TYPE t_string IS TABLE OF string_type;
			   TYPE t_param IS TABLE OF string_type INDEX BY param_type;
			   TYPE t_lov IS TABLE OF t_string INDEX BY param_type;
			
			   /**
			   * Get name of the generator, used in tree view
			   *
			   * @returns name of the generator
			   */
			   FUNCTION get_name RETURN VARCHAR2;
			
			   /**
			   * Get a description of the generator.
			   * 
			   * @returns description of the generator
			   */
			   FUNCTION get_description RETURN VARCHAR2;
			
			   /**
			   * Get a list of supported object types.
			   *
			   * @returns a list of supported object types
			   */
			   FUNCTION get_object_types RETURN t_string;
			
			   /**
			   * Get a list of objects for a object type.
			   *
			   * @param in_object_type object type to filter objects
			   * @returns a list of objects
			   */
			   FUNCTION get_object_names(in_object_type IN VARCHAR2) RETURN t_string;
			
			   /**
			   * Get all parameters supported by the generator including default values.
			   *
			   * @returns parameters supported by the generator
			   */
			   FUNCTION get_params RETURN t_param;
			   
			  /**
			   * Get all parameter names in the order to be displayed in the 
			   * generate dialog.
			   *
			   * @returns ordered parameter names
			   */
			   FUNCTION get_ordered_params RETURN t_string;  
			
			   /**
			   * Get a list of values per parameter, if such a LOV is applicable.
			   *
			   * @returns parameters with their list-of-values
			   */
			   FUNCTION get_lov RETURN t_lov;
			
			   /**
			   * Enables/disables co_iot_suffix based on co_gen_iot
			   *
			   * @param in_params parameters to configure the behavior of the generator
			   * @returns parameters with their editable state ("0"=disabled, "1"=enabled)
			   */
			   FUNCTION refresh_param_states(in_params IN t_param) RETURN t_param;
			
			   /**
			   * Generates the result.
			   *
			   * @param in_object_type object type to process
			   * @param in_object_name object_name of in_object_type to process
			   * @param in_params parameters to configure the behavior of the generator
			   * @returns generator output
			   * @throws ORA-20501 when parameter validation fails
			   */
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2,
			                     in_params      IN t_param) RETURN CLOB;
			
			   /**
			   * Alternative, simplified version of the generator, which is applicable in SQL.
			   * Default values according get_params are used for in_params.
			   * This function is implemented for convenience purposes only.
			   *
			   * @param in_object_type object type to process
			   * @param in_object_name object_name of in_object_type to process
			   * @returns generator output
			   * @throws ORA-20501 when parameter validation fails
			   */
			   FUNCTION generate(in_object_type IN VARCHAR2, in_object_name IN VARCHAR2) RETURN CLOB;
			END plsql_view;
		''')

		// create package body of plsql_view generator
		// copy of oddgen/examples/package/plsql/plsql_view.pkb
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE BODY plsql_view IS
			   /*
			   * Copyright 2015-2016 Philipp Salvisberg <philipp.salvisberg@trivadis.com>
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
			
			   --
			   -- parameter names used also as labels in the GUI
			   --
			   co_view_suffix  CONSTANT param_type := 'View suffix';
			   co_table_suffix CONSTANT param_type := 'Table suffix to be replaced';
			   co_iot_suffix   CONSTANT param_type := 'Instead-of-trigger suffix';
			   co_gen_iot      CONSTANT param_type := 'Generate instead-of-trigger?';
			
			   --
			   -- other constants
			   --
			   c_new_line      CONSTANT string_type := chr(10);
			   co_max_obj_len  CONSTANT PLS_INTEGER := 30;
			   co_oddgen_error CONSTANT PLS_INTEGER := -20501;
			
			   --
			   -- get_name
			   --
			   FUNCTION get_name RETURN VARCHAR2 IS
			   BEGIN
			      RETURN '1:1 View (PL/SQL)';
			   END get_name;
			
			   --
			   -- get_description
			   --
			   FUNCTION get_description RETURN VARCHAR2 IS
			   BEGIN
			      RETURN 'Generates a 1:1 view based on an existing table. Optionally generates a simple instead of trigger. The generator is based on plain PL/SQL without a third party template engine.';
			   END get_description;
			
			   --
			   -- get_object_types
			   --
			   FUNCTION get_object_types RETURN t_string IS
			   BEGIN
			      RETURN NEW t_string('TABLE');
			   END get_object_types;
			
			   --
			   -- get_object_names
			   --
			   FUNCTION get_object_names(in_object_type IN VARCHAR2) RETURN t_string IS
			      l_object_names t_string;
			   BEGIN
			      SELECT object_name
			        BULK COLLECT
			        INTO l_object_names
			        FROM user_objects
			       WHERE object_type = in_object_type
			             AND generated = 'N'
			       ORDER BY object_name;
			      RETURN l_object_names;
			   END get_object_names;
			
			   --
			   -- get_params
			   --
			   FUNCTION get_params RETURN t_param IS
			      l_params t_param;
			   BEGIN
			      l_params(co_view_suffix) := '_V';
			      l_params(co_table_suffix) := '_T';
			      l_params(co_iot_suffix) := '_TRG';
			      l_params(co_gen_iot) := 'Yes';
			      RETURN l_params;
			   END get_params;
			   
			   --
			   -- get_ordered_params
			   --
			   FUNCTION get_ordered_params RETURN t_string IS
			      l_ordered_params t_string;
			   BEGIN
			      l_ordered_params := NEW t_string();
			      l_ordered_params.extend(3);
			      l_ordered_params(1) := co_view_suffix;
			      l_ordered_params(2) := co_table_suffix;
			      l_ordered_params(3) := co_gen_iot;
			      RETURN l_ordered_params;
			   END get_ordered_params;
			
			   --
			   -- get_lov
			   --
			   FUNCTION get_lov RETURN t_lov IS
			      l_lov t_lov;
			   BEGIN
			      l_lov(co_gen_iot) := NEW t_string('Yes', 'No');
			      RETURN l_lov;
			   END get_lov;
			
			   --
			   -- refresh_param_states
			   --
			   FUNCTION refresh_param_states(in_params IN t_param) RETURN t_param IS
			   
			      l_param_states t_param;
			   BEGIN
			      IF in_params(co_gen_iot) = 'Yes' THEN
			         l_param_states(co_iot_suffix) := '1'; -- enable
			      ELSE
			         l_param_states(co_iot_suffix) := '0'; -- disable
			      END IF;
			      RETURN l_param_states;
			   END refresh_param_states;
			
			   --
			   -- generate (1)
			   --
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2,
			                     in_params      IN t_param) RETURN CLOB IS
			      l_result CLOB;
			      l_params t_param;
			      --
			      CURSOR c_columns IS
			         SELECT column_name,
			                CASE
			                    WHEN column_id = min_column_id THEN
			                     1
			                    ELSE
			                     0
			                 END AS is_first,
			                CASE
			                    WHEN column_id = max_column_id THEN
			                     1
			                    ELSE
			                     0
			                 END AS is_last
			           FROM (SELECT column_name,
			                        column_id,
			                        MIN(column_id) over() AS min_column_id,
			                        MAX(column_id) over() AS max_column_id
			                   FROM user_tab_columns
			                  WHERE table_name = in_object_name)
			          ORDER BY column_id;
			      --
			      CURSOR c_pk_columns IS
			         SELECT column_name,
			                CASE
			                    WHEN position = min_position THEN
			                     1
			                    ELSE
			                     0
			                 END AS is_first
			           FROM (SELECT cols.column_name,
			                        cols.position,
			                        MIN(cols.position) over() AS min_position
			                   FROM user_constraints pk
			                   JOIN user_cons_columns cols
			                     ON cols.constraint_name = pk.constraint_name
			                  WHERE pk.constraint_type = 'P'
			                        AND pk.table_name = in_object_name)
			          ORDER BY position;
			      --
			      FUNCTION get_base_name RETURN VARCHAR2 IS
			         l_base_name string_type;
			      BEGIN
			         IF l_params(co_table_suffix) IS NOT NULL AND
			            length(l_params(co_table_suffix)) > 0 AND
			            substr(in_object_name,
			                   length(in_object_name) - length(l_params(co_table_suffix))) =
			            l_params(co_table_suffix) THEN
			            l_base_name := substr(in_object_name,
			                                  1,
			                                  length(in_object_name) -
			                                  length(l_params(co_table_suffix)));
			         ELSE
			            l_base_name := in_object_name;
			         END IF;
			         RETURN l_base_name;
			      END get_base_name;
			      --
			      FUNCTION get_name(suffix_in IN VARCHAR2) RETURN VARCHAR2 IS
			         l_name string_type;
			      BEGIN
			         l_name := get_base_name;
			         IF length(l_name) + length(suffix_in) > co_max_obj_len THEN
			            l_name := substr(l_name, 1, co_max_obj_len - length(suffix_in));
			         END IF;
			         l_name := l_name || suffix_in;
			         RETURN l_name;
			      END get_name;
			      --
			      FUNCTION get_view_name RETURN VARCHAR2 IS
			      BEGIN
			         RETURN get_name(l_params(co_view_suffix));
			      END get_view_name;
			      --
			      FUNCTION get_iot_name RETURN VARCHAR2 IS
			      BEGIN
			         RETURN get_name(l_params(co_iot_suffix));
			      END get_iot_name;
			      --
			      PROCEDURE check_params IS
			         l_found  BOOLEAN;
			         r_col    c_columns%ROWTYPE;
			         r_pk_col c_pk_columns%ROWTYPE;
			      BEGIN
			         OPEN c_columns;
			         FETCH c_columns
			            INTO r_col;
			         l_found := c_columns%FOUND;
			         CLOSE c_columns;
			         IF NOT l_found THEN
			            raise_application_error(co_oddgen_error,
			                                    'Table ' || in_object_name || ' not found.');
			         END IF;
			         IF get_view_name = in_object_name THEN
			            raise_application_error(co_oddgen_error,
			                                    'Change <' || co_view_suffix ||
			                                    '>. The target view must be named differently than its base table.');
			         END IF;
			         IF l_params(co_gen_iot) NOT IN ('Yes', 'No') THEN
			            raise_application_error(co_oddgen_error,
			                                    'Invalid value <' || l_params(co_gen_iot) ||
			                                    '> for parameter <' || co_gen_iot ||
			                                    '>. Valid are Yes and No.');
			         END IF;
			         IF l_params(co_gen_iot) = 'Yes' THEN
			            IF get_iot_name = get_view_name OR get_iot_name = in_object_name THEN
			               raise_application_error(co_oddgen_error,
			                                       'Change <' || co_iot_suffix ||
			                                       '>. The target instead-of-trigger must be named differently than its base view and base table.');
			            END IF;
			            OPEN c_pk_columns;
			            FETCH c_pk_columns
			               INTO r_pk_col;
			            l_found := c_pk_columns%FOUND;
			            CLOSE c_pk_columns;
			            IF NOT l_found THEN
			               raise_application_error(co_oddgen_error,
			                                       'No primary key found in table ' || in_object_name ||
			                                       '. Cannot generate instead-of-trigger.');
			            END IF;
			         END IF;
			      END check_params;
			      --
			      PROCEDURE init_params IS
			         i string_type;
			      BEGIN
			         l_params := get_params;
			         IF in_params.count() > 0 THEN
			            i := in_params.first();
			            <<input_params>>
			            WHILE (i IS NOT NULL)
			            LOOP
			               IF l_params.exists(i) THEN
			                  l_params(i) := in_params(i);
			                  i := in_params.next(i);
			               ELSE
			                  raise_application_error(co_oddgen_error,
			                                          'Parameter <' || i || '> is not known.');
			               END IF;
			            END LOOP input_params;
			         END IF;
			         check_params;
			      END init_params;
			      --
			      PROCEDURE add_line(line_in IN VARCHAR2) IS
			      BEGIN
			         l_result := l_result || line_in || c_new_line;
			      END add_line;
			      --
			      PROCEDURE gen_view IS
			         l_line string_type;
			      BEGIN
			         add_line('-- create 1:1 view for demonstration purposes');
			         add_line('CREATE OR REPLACE VIEW ' || get_view_name() || ' AS');
			         <<select_list>>
			         FOR l_rec IN c_columns
			         LOOP
			            IF l_rec.is_first = 1 THEN
			               l_line := '   SELECT ';
			            ELSE
			               l_line := '          ';
			            END IF;
			            l_line := l_line || l_rec.column_name;
			            IF l_rec.is_last = 0 THEN
			               l_line := l_line || ',';
			            END IF;
			            add_line(l_line);
			         END LOOP select_list;
			         add_line('     FROM ' || in_object_name || ';');
			      END gen_view;
			      --
			      FUNCTION get_where_clause RETURN VARCHAR2 IS
			         l_where string_type;
			         l_line  string_type;
			      BEGIN
			         <<pk_columns>>
			         FOR l_rec IN c_pk_columns
			         LOOP
			            IF l_rec.is_first = 1 THEN
			               l_line := '       WHERE ';
			            ELSE
			               l_line := c_new_line || '         AND ';
			            END IF;
			            l_line  := l_line || l_rec.column_name || ' = :OLD.' || l_rec.column_name;
			            l_where := l_where || l_line;
			         END LOOP pk_columns;
			         RETURN l_where;
			      END get_where_clause;
			      --
			      PROCEDURE gen_iot IS
			         l_line string_type;
			      BEGIN
			         IF l_params(co_gen_iot) = 'Yes' THEN
			            add_line('-- create simple instead-of-trigger for demonstration purposes');
			            add_line('CREATE OR REPLACE TRIGGER ' || get_iot_name);
			            add_line('   INSTEAD OF INSERT OR UPDATE OR DELETE ON ' || get_view_name);
			            add_line('BEGIN');
			            add_line('   IF INSERTING THEN');
			            add_line('      INSERT INTO ' || in_object_name || ' (');
			            <<insert_column_list>>
			            FOR l_rec IN c_columns
			            LOOP
			               l_line := '         ' || l_rec.column_name;
			               IF l_rec.is_last = 0 THEN
			                  l_line := l_line || ',';
			               END IF;
			               add_line(l_line);
			            END LOOP insert_column_list;
			            add_line('      ) VALUES (');
			            <<insert_value_list>>
			            FOR l_rec IN c_columns
			            LOOP
			               l_line := '         :NEW.' || l_rec.column_name;
			               IF l_rec.is_last = 0 THEN
			                  l_line := l_line || ',';
			               END IF;
			               add_line(l_line);
			            END LOOP insert_value_list;
			            add_line('      );');
			            add_line('   ELSIF UPDATING THEN');
			            add_line('      UPDATE ' || in_object_name);
			            <<update_set_clause>>
			            FOR l_rec IN c_columns
			            LOOP
			               IF l_rec.is_first = 1 THEN
			                  l_line := '         SET ';
			               ELSE
			                  l_line := '             ';
			               END IF;
			               l_line := l_line || l_rec.column_name || ' = :NEW.' || l_rec.column_name;
			               IF l_rec.is_last = 0 THEN
			                  l_line := l_line || ',';
			               END IF;
			               add_line(l_line);
			            END LOOP update_set_clause;
			            add_line(get_where_clause || ';');
			            add_line('   ELSIF DELETING THEN');
			            add_line('      DELETE FROM ' || in_object_name);
			            add_line(get_where_clause() || ';');
			            add_line('   END IF;');
			            add_line('END;');
			            add_line('/');
			         END IF;
			      END gen_iot;
			   BEGIN
			      IF in_object_type = 'TABLE' THEN
			         init_params;
			         gen_view;
			         gen_iot;
			      ELSE
			         raise_application_error(co_oddgen_error,
			                                 '<' || in_object_type ||
			                                 '> is not a supported object type. Please use TABLE.');
			      END IF;
			      RETURN l_result;
			   END generate;
			
			   --
			   -- generate (2)
			   --
			   FUNCTION generate(in_object_type IN VARCHAR2, in_object_name IN VARCHAR2) RETURN CLOB IS
			      l_params t_param;
			   BEGIN
			      RETURN generate(in_object_type => in_object_type,
			                      in_object_name => in_object_name,
			                      in_params      => l_params);
			   END generate;
			END plsql_view;
		''')
	}

	def static createPlsqlDummy() {
		// create package specification of dummy generator with refresh_lov function
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE plsql_dummy AUTHID CURRENT_USER IS
			   SUBTYPE string_type IS VARCHAR2(1000 CHAR);
			   SUBTYPE param_type IS VARCHAR2(30 CHAR);
			   TYPE t_string IS TABLE OF string_type;
			   TYPE t_param IS TABLE OF string_type INDEX BY param_type;
			   TYPE t_lov IS TABLE OF t_string INDEX BY param_type;
			
			   FUNCTION get_params RETURN t_param;
			
			   FUNCTION get_lov RETURN t_lov;
			
			   FUNCTION refresh_lov(in_object_type IN VARCHAR2,
			                        in_object_name IN VARCHAR2,
			                        in_params      IN t_param) RETURN t_lov;
			
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2,
			                     in_params      IN t_param) RETURN CLOB;
			END plsql_dummy;
		''')

		// create package body of dummy generator with refresh_lov function
		jdbcTemplate.execute('''
			CREATE OR REPLACE PACKAGE BODY plsql_dummy IS
			   FUNCTION get_params RETURN t_param IS
			      l_params t_param;
			   BEGIN
			      l_params('With children?') := 'Yes';
			      l_params('With grandchildren?') := 'Yes';
			      RETURN l_params;
			   END get_params;
			
			   FUNCTION get_lov RETURN t_lov IS
			      l_lov t_lov;
			   BEGIN
			      l_lov('With children?') := NEW t_string('Yes', 'No');
			      l_lov('With grandchildren?') := NEW t_string('Yes', 'No');
			      RETURN l_lov;
			   END get_lov;
			
			   FUNCTION refresh_lov(in_object_type IN VARCHAR2,
			                        in_object_name IN VARCHAR2,
			                        in_params      IN t_param) RETURN t_lov IS
			      l_lov t_lov;
			   BEGIN
			      l_lov('With children?') := NEW t_string('Yes', 'No');
			      IF in_params('With children?') = 'Yes' THEN
			         l_lov('With grandchildren?') := NEW t_string('Yes', 'No');
			      ELSE
			         l_lov('With grandchildren?') := NEW t_string('No');
			      END IF;
			      RETURN l_lov;
			   END refresh_lov;
			
			   FUNCTION generate(in_object_type IN VARCHAR2,
			                     in_object_name IN VARCHAR2,
			                     in_params      IN t_param) RETURN CLOB IS
			      l_result CLOB;
			   BEGIN
			      l_result := 'Object type: ' || in_object_type;
			      l_result := l_result || chr(10) || 'Object name: ' || in_object_name;
			      l_result := l_result || chr(10) || 'With children: ' || in_params('With children?');
			      l_result := l_result || chr(10) || 'With grandchildren: ' || in_params('With grandchildren?');
			      RETURN l_result;
			   END generate;
			END plsql_dummy;
		''')
	}

}
