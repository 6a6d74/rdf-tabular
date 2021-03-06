require 'rdf'

module RDF::Tabular
  ##
  # A Tabular Data to RDF parser in Ruby.
  #
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Reader < RDF::Reader
    format Format
    include Utils

    # Metadata associated with the CSV
    #
    # @return [Metadata]
    attr_reader :metadata

    ##
    # Input open to read
    # @return [:read]
    attr_reader :input

    ##
    # Initializes the RDF::Tabular Reader instance.
    #
    # @param  [Util::File::RemoteDoc, IO, StringIO, Array<Array<String>>]       input
    #   An opened file possibly JSON Metadata,
    #   or an Array used as an internalized array of arrays
    # @param  [Hash{Symbol => Object}] options
    #   any additional options (see `RDF::Reader#initialize`)
    # @option options [Metadata, Hash, String, RDF::URI] :metadata user supplied metadata, merged on top of extracted metadata. If provided as a URL, Metadata is loade from that location
    # @option options [Boolean] :minimal includes only the information gleaned from the cells of the tabular data
    # @option options [Boolean] :noProv do not output optional provenance information
    # @yield  [reader] `self`
    # @yieldparam  [RDF::Reader] reader
    # @yieldreturn [void] ignored
    # @raise [RDF::ReaderError] if the CSV document cannot be loaded
    def initialize(input = $stdin, options = {}, &block)
      super do
        # Base would be how we are to take this
        @options[:base] ||= base_uri.to_s if base_uri
        @options[:base] ||= input.base_uri if input.respond_to?(:base_uri)
        @options[:base] ||= input.path if input.respond_to?(:path)
        @options[:base] ||= input.filename if input.respond_to?(:filename)
        @options[:depth] ||= 0

        debug("Reader#initialize") {"input: #{input.inspect}, base: #{@options[:base]}"}

        # Minimal implies noProv
        @options[:noProv] ||= @options[:minimal]

        @input = input.is_a?(String) ? StringIO.new(input) : input

        depth do
          # If input is JSON, then the input is the metadata
          if @options[:base] =~ /\.json(?:ld)?$/ ||
             @input.respond_to?(:content_type) && @input.content_type =~ %r(application/(?:ld+)json)
            @metadata = @input = Metadata.new(@input, @options)
          else
            # HTTP flags
            if @input.respond_to?(:headers) &&
               input.headers.fetch(:content_type, '').split(';').include?('header=absent')
              @options[:metadata] ||= TableGroup.new(dialect: {header: false})
            end
            # Otherwise, it's tabluar data
            @metadata = Metadata.for_input(@input, @options)

            # If metadata is a TableGroup, get metadata for this table
            @metadata = @metadata.for_table(@options[:base]) if @metadata.is_a?(TableGroup)
          end

          debug("Reader#initialize") {"input: #{input}, metadata: #{metadata.inspect}"}

          if block_given?
            case block.arity
              when 0 then instance_eval(&block)
              else block.call(self)
            end
          end
        end
      end
    end

    ##
    # @private
    # @see   RDF::Reader#each_statement
    def each_statement(&block)
      if block_given?
        @callback = block

        start_time = Time.now

        # Construct metadata from that passed from file open, along with information from the file.
        if input.is_a?(Metadata)
          debug("each_statement: metadata") {input.inspect}
          depth do
            # Get Metadata to invoke and open referenced files
            case input.type
            when :TableGroup
              # Use resolved @id of TableGroup, if available
              table_group = input.id || RDF::Node.new
              add_statement(0, table_group, RDF.type, CSVW.TableGroup) unless minimal?

              # Common Properties
              input.each do |key, value|
                next unless key.to_s.include?(':')
                input.common_properties(table_group, key, value) do |statement|
                  add_statement(0, statement)
                end
              end unless minimal?

              input.each_resource do |table|
                next if table.suppressOutput
                table_resource = table.id || RDF::Node.new
                add_statement(0, table_group, CSVW.resources, table_resource) unless minimal?
                Reader.open(table.url, options.merge(
                    format: :tabular,
                    metadata: table,
                    base: table.url,
                    no_found_metadata: true,
                    table_resource: table_resource
                )) do |r|
                  r.each_statement(&block)
                end
              end
            when :Table
              Reader.open(input.url, options.merge(format: :tabular, metadata: input, base: input.url, no_found_metadata: true)) do |r|
                r.each_statement(&block)
              end
            else
              raise "Opened inappropriate metadata type: #{input.type}"
            end
          end
          return
        end

        # Output Table-Level RDF triples
        # SPEC CONFUSION: Would we ever use the resolved @id of the Table metadata?
        table_resource = options.fetch(:table_resource, (metadata.id || RDF::Node.new))
        unless minimal?
          add_statement(0, table_resource, RDF.type, CSVW.Table)
          add_statement(0, table_resource, CSVW.url, RDF::URI(metadata.url))
        end

        # Common Properties
        metadata.each do |key, value|
          next unless key.to_s.include?(':') || key == :notes
          metadata.common_properties(table_resource, key, value) do |statement|
            add_statement(0, statement)
          end
        end unless minimal?

        # Input is file containing CSV data.
        # Output ROW-Level statements
        metadata.each_row(input) do |row|
          # Output row-level metadata
          row_resource = RDF::Node.new
          default_cell_subject = RDF::Node.new
          unless minimal?
            add_statement(row.sourceNumber, table_resource, CSVW.row, row_resource)
            add_statement(row.sourceNumber, row_resource, CSVW.rownum, row.number)
            add_statement(row.sourceNumber, row_resource, CSVW.url, RDF::URI(metadata.url) + "#row=#{row.sourceNumber}")
          end
          row.values.each_with_index do |cell, index|
            next if cell.column.suppressOutput # Skip ignored cells
            cell_subject = cell.aboutUrl || default_cell_subject
            add_statement(row.sourceNumber, row_resource, CSVW.describes, cell_subject) unless minimal?

            if cell.valueUrl
              add_statement(row.sourceNumber, cell_subject, cell.propertyUrl, cell.valueUrl)
            elsif cell.column.ordered
              list = RDF::List[*Array(cell.value)]
              add_statement(row.sourceNumber, cell_subject, cell.propertyUrl, list.subject)
              list.each_statement do |statement|
                next if statement.predicate == RDF.type && statement.object == RDF.List
                add_statement(row.sourceNumber, statement.subject, statement.predicate, statement.object)
              end
            else
              Array(cell.value).each do |v|
                add_statement(row.sourceNumber, cell_subject, cell.propertyUrl, v)
              end
            end
          end
        end

        # Provenance
        unless @options[:noProv]
          # Distribution
          distribution = RDF::Node.new
          add_statement(0, table_resource, RDF::DCAT.distribution, distribution)
          add_statement(0, distribution, RDF.type, RDF::DCAT.Distribution)
          add_statement(0, distribution, RDF::DCAT.downloadURL, metadata.url)

          activity = RDF::Node.new
          add_statement(0, table_resource, RDF::PROV.activity, activity)
          add_statement(0, activity, RDF.type, RDF::PROV.Activity)
          add_statement(0, activity, RDF::PROV.startedAtTime, RDF::Literal::DateTime.new(start_time))
          add_statement(0, activity, RDF::PROV.endedAtTime, RDF::Literal::DateTime.new(Time.now))

          csv_path = @options[:base]

          if csv_path
            usage = RDF::Node.new
            add_statement(0, activity, RDF::PROV.qualifiedUsage, usage)
            add_statement(0, usage, RDF.type, RDF::PROV.Usage)
            add_statement(0, usage, RDF::PROV.Entity, RDF::URI(csv_path))
            # FIXME: needs to be defined in vocabulary
            add_statement(0, usage, RDF::PROV.hadRole, CSVW.to_uri + "csvEncodedTabularData")
          end

          Array(@metadata.filenames).each do |fn|
            usage = RDF::Node.new
            add_statement(0, activity, RDF::PROV.qualifiedUsage, usage)
            add_statement(0, usage, RDF.type, RDF::PROV.Usage)
            add_statement(0, usage, RDF::PROV.Entity, RDF::URI(fn))
            # FIXME: needs to be defined in vocabulary
            add_statement(0, usage, RDF::PROV.hadRole, CSVW.to_uri + "tabularMetadata")
          end
        end
      end
      enum_for(:each_statement)
    end

    ##
    # @private
    # @see   RDF::Reader#each_triple
    def each_triple(&block)
      if block_given?
        each_statement do |statement|
          block.call(*statement.to_triple)
        end
      end
      enum_for(:each_triple)
    end

    ##
    # Transform to JSON. Note that this must be run from within the reader context if the input is an open IO stream.
    #
    # @example outputing annotated CSV as JSON
    #     result = nil
    #     RDF::Tabular::Reader.open("etc/doap.csv") do |reader|
    #       result = reader.to_json
    #     end
    #     result #=> {...}
    #
    # @example outputing annotated CSV as JSON from an in-memory structure
    #     csv = %(
    #       GID,On Street,Species,Trim Cycle,Inventory Date
    #       1,ADDISON AV,Celtis australis,Large Tree Routine Prune,10/18/2010
    #       2,EMERSON ST,Liquidambar styraciflua,Large Tree Routine Prune,6/2/2010
    #       3,EMERSON ST,Liquidambar styraciflua,Large Tree Routine Prune,6/2/2010
    #     ).gsub(/^\s+/, '')
    #     r = RDF::Tabular::Reader.new(csv)
    #     r.to_json #=> {...}
    #
    # @param [Hash{Symbol => Object}] options may also be a JSON state
    # @option options [IO, StringIO] io to output to file
    # @option options [::JSON::State] :state used when dumping
    # @option options [Boolean] :atd output Abstract Table representation instead
    # @return [String]
    def to_json(options = {})
      hash_fn = options[:atd] ? :to_atd : :to_hash
      if options[:io]
        ::JSON::dump_default_options = options.fetch(:state, ::JSON::LD::JSON_STATE)
        ::JSON.dump(self.send(hash_fn, options), options[:io])
      else
        hash = self.send(hash_fn, options.is_a?(Hash) ? options : {})
        state = (options[:state] if options.is_a?(Hash)) || options
        ::JSON.generate(hash, state)
      end
    end

    ##
    # Return a hash representation of the data for JSON serialization
    # @param [Hash{Symbol => Object}] options
    # @return [Hash]
    def to_hash(options = {})
      # Construct metadata from that passed from file open, along with information from the file.
      if input.is_a?(Metadata)
        debug("each_statement: metadata") {input.inspect}
        depth do
          # Get Metadata to invoke and open referenced files
          case input.type
          when :TableGroup
            tables = []
            table_group = {"tables" => tables}

            # Common Properties
            table_group.merge!(input.common_properties)

            input.each_resource do |table|
              Reader.open(table.url, options.merge(
                format:             :tabular,
                metadata:           table,
                base:               table.url,
                no_found_metadata:  true,
                noProv:             true
              )) do |r|
                tables << r.to_hash(options)
              end
            end

            # Optional describedBy
            # Provenance
            if Array(input.filenames).length > 0 && !@options[:noProv]
              table_group["describedBy"] = input.filenames.length == 1 ? input.filenames.first : input.filenames
            end

            # Result is table_group
            table_group
          when :Table
            table = nil
            Reader.open(input.url, options.merge(
              format:             :tabular,
              metadata:           input,
              base:               input.url,
              no_found_metadata:  true,
              noProv:             true
            )) do |r|
              table = r.to_hash(options)
            end

            # Optional describedBy
            # Provenance
            if Array(input.filenames).length > 0 && !@options[:noProv]
              table["describedBy"] = input.filenames.length == 1 ? input.filenames.first : input.filenames
            end

            table
          else
            raise "Opened inappropriate metadata type: #{input.type}"
          end
        end
      else
        rows = []
        table = {"url" => metadata.url.to_s,}

        # Use string values notes and common properties
        metadata.common_properties.each do |prop, value|
          value = [value] unless value.is_a?(Array)
          value = value.map do |v|
            if v.is_a?(Hash) && !(v.keys & %w(@id @value)).empty?
              v['@value'] || v['@id']
            else
              v
            end
          end
          table[prop] = value.length == 1 ? value.first : value
        end

        table.merge!("row" => rows)

        # Input is file containing CSV data.
        # Output ROW-Level statements
        metadata.each_row(input) do |row|
          # Output row-level metadata
          r = {}
          r["url"] = row.resource.to_s if row.resource.is_a?(RDF::URI)
          r["rownum"] = row.number

          row.values.each_with_index do |cell, index|
            column = metadata.tableSchema.columns[index]

            # Ignore vitual columns
            next if column.virtual

            r[column.name] = cell.valueUrl || cell.value
          end
          rows << r
        end

        # Provenance
        unless @options[:noProv]
          table['distribution'] = { "downloadURL" => metadata.url}

          # Optional describedBy
          if Array(@metadata.filenames).length > 0
            table["describedBy"] = @metadata.filenames.length == 1 ? @metadata.filenames.first : @metadata.filenames
          end
        end
        table
      end
    end

    # Return a hash representation of the annotated tabular data model for JSON serialization
    # @param [Hash{Symbol => Object}] options
    # @return [Hash]
    def to_atd(options = {})
      # Construct metadata from that passed from file open, along with information from the file.
      if input.is_a?(Metadata)
        debug("each_statement: metadata") {input.inspect}
        depth do
          # Get Metadata to invoke and open referenced files
          case input.type
          when :TableGroup
            table_group = input.to_atd

            input.each_resource do |table|
              Reader.open(table.url, options.merge(
                format:             :tabular,
                metadata:           table,
                base:               table.url,
                no_found_metadata:  true, # FIXME: remove
                noProv:             true
              )) do |r|
                table = r.to_atd(options)
                
                # Fill in columns and rows in table_group entry from returned table
                t = table_group[:resources].detect {|tab| tab["url"] == table["url"]}
                t["columns"] = table["columns"]
                t["rows"] = table["rows"]
              end
            end

            # Result is table_group
            table_group
          when :Table
            table = nil
            Reader.open(input.url, options.merge(
              format:             :tabular,
              metadata:           input,
              base:               input.url,
              no_found_metadata:  true,
              noProv:             true
            )) do |r|
              table = r.to_atd(options)
            end

            table
          else
            raise "Opened inappropriate metadata type: #{input.type}"
          end
        end
      else
        rows = []
        table = metadata.to_atd
        rows, columns = table["rows"], table["columns"]

        # Input is file containing CSV data.
        # Output ROW-Level statements
        metadata.each_row(input) do |row|
          rows << row.to_atd
          row.values.each_with_index do |cell, colndx|
            columns[colndx]["cells"] << cell.id
          end
        end
        table
      end
    end

    def minimal?; @options[:minimal]; end
    def prov?; !(@options[:noProv]); end

    private
    ##
    # @overload add_statement(lineno, statement)
    #   Add a statement, object can be literal or URI or bnode
    #   @param [String] lineno
    #   @param [RDF::Statement] statement
    #   @yield [RDF::Statement]
    #   @raise [ReaderError] Checks parameter types and raises if they are incorrect if parsing mode is _validate_.
    #
    # @overload add_statement(lineno, subject, predicate, object)
    #   Add a triple
    #   @param [URI, BNode] subject the subject of the statement
    #   @param [URI] predicate the predicate of the statement
    #   @param [URI, BNode, Literal] object the object of the statement
    #   @raise [ReaderError] Checks parameter types and raises if they are incorrect if parsing mode is _validate_.
    def add_statement(node, *args)
      statement = args[0].is_a?(RDF::Statement) ? args[0] : RDF::Statement.new(*args)
      raise RDF::ReaderError, "#{statement.inspect} is invalid" if validate? && statement.invalid?
      debug(node) {"statement: #{RDF::NTriples.serialize(statement)}".chomp}
      @callback.call(statement)
    end

  end
end

