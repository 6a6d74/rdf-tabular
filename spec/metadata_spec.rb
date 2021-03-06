# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe RDF::Tabular::Metadata do
  before(:each) do
    WebMock.stub_request(:any, %r(.*example.org.*)).
      to_return(lambda {|request|
        file = request.uri.to_s.split('/').last
        content_type = case file
        when /\.json/ then 'application/json'
        when /\.csv/  then 'text/csv'
        else 'text/plain'
        end

        case file
        when "metadata.json", "country-codes-and-names.csv-metadata.json"
          {status: 401}
        else
          {
            body: File.read(File.expand_path("../data/#{file}", __FILE__)),
            status: 200,
            headers: {'Content-Type' => content_type}
          }
        end
      })
    @debug = []
  end

  shared_examples "inherited properties" do |allowed = true|
    {
      null: {
        valid: ["foo"],
        invalid: [1, true, {}]
      },
      lang: {
        valid: %w(en en-US),
        invalid: %w(1 foo)
      },
      "textDirection" => {
        valid: %w(rtl ltr),
        invalid: %w(foo default)
      },
      separator: {
        valid: %w(, a | :),
        invalid: [1, false, nil] + %w(foo ::)
      },
      ordered: {
        valid: [true, false, 1, 0, "true", "false", "TrUe", "fAlSe", "1", "0"],
        invalid: [nil, "foo"],
      },
      default: {
        valid: ["foo"],
        invalid: [1, true, nil]
      },
      datatype: {
        valid: (%w(anyAtomicType string token language Name NCName boolean gYear number binary datetime any xml html json) +
               [
                 {"base" => "string"} #, FIXME ...
               ]),
        invalid: [1, true, "foo", "anySimpleType", "IDREFS"]
      },
      aboutUrl: {
        valid: ["http://example.org/example.csv#row={_row}", "http://example.org/tree/{on%2Dstreet}/{GID}", "#row.{_row}"],
        invalid: [1, true, nil, %w(foo bar)]
      },
      propertyUrl: {
        valid: [
          "http://example.org/example.csv#col={_name}",
          "http://example.org/tree/{on%2Dstreet}/{GID}",
          "#row.{_row}"
        ],
        invalid: [1, true, %w(foo bar)]
      },
      valueUrl: {
        valid: [
          "http://example.org/example.csv#row={_row}",
          "http://example.org/tree/{on%2Dstreet}/{GID}",
          "#row.{_row}"
        ],
        invalid: [1, true, nil, %w(foo bar)]
      },
    }.each do |prop, params|
      context prop.to_s do
        if allowed
          it "validates" do
            params[:valid].each do |v|
              subject.send("#{prop}=".to_sym, v)
              expect(subject.errors).to be_empty
            end
          end
          it "invalidates" do
            params[:invalid].each do |v|
              subject.send("#{prop}=".to_sym, v)
              subject.valid?
              expect(subject.errors).not_to be_empty
            end
          end
        else
          it "does not allow" do
            params[:valid].each do |v|
              subject.send("#{prop}=".to_sym, v)
              expect(subject.errors).not_to be_empty
            end
          end
        end
      end
    end
  end

  shared_examples "common properties" do |allowed = true|
    let(:valid) {%w(dc:description dcat:keyword http://schema.org/copyrightHolder)}
    let(:invalid) {%w(foo bar:baz)}
    if allowed
      it "allows defined prefixed names and absolute URIs" do
        valid.each do |v|
          subject[v.to_sym] = "foo"
          expect(subject.errors).to be_empty
        end
      end

      it "Does not allow unknown prefxies or unprefixed names" do
        invalid.each do |v|
          subject[v.to_sym] = "foo"
          expect(subject.errors).not_to be_empty
        end
      end
    else
      it "Does not allow defined prefixed names and absolute URIs" do
        (valid + invalid).each do |v|
          subject[v.to_sym] = "foo"
          expect(subject.errors).not_to be_empty
        end
      end
    end
  end

  describe RDF::Tabular::Column do
    subject {described_class.new({"name" => "foo"}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    specify {is_expected.to be_valid}
    it_behaves_like("inherited properties")
    it_behaves_like("common properties")

    it "allows valid name" do
      %w(
        name abc.123 _col.1
      ).each {|v| expect(described_class.new("name" => v)).to be_valid}
    end

    it "detects invalid names" do
      [1, true, nil, "_foo", "_col=1"].each {|v| expect(described_class.new("name" => v)).not_to be_valid}
    end

    it "allows absence of name" do
      expect(described_class.new("@type" => "Column")).to be_valid
      expect(described_class.new("@type" => "Column").name).to eql '_col.0'
    end

    its(:type) {is_expected.to eql :Column}

    {
      title: {
        valid: ["foo", %w(foo bar), {"en" => "foo", "de" => "bar"}],
        invalid: [1, true, nil]
      },
      required: {
        valid: [true, false, 1, 0, "true", "false", "TrUe", "fAlSe", "1", "0"],
        invalid: [nil, "foo"],
      },
      virtual: {
        valid: [true, false, 1, 0, "true", "false", "TrUe", "fAlSe", "1", "0"],
        invalid: [nil, "foo"],
      },
    }.each do |prop, params|
      context prop.to_s do
        it "validates" do
          params[:valid].each do |v|
            subject.send("#{prop}=".to_sym, v)
            expect(subject).to be_valid
          end
        end
        it "invalidates" do
          params[:invalid].each do |v|
            subject.send("#{prop}=".to_sym, v)
            expect(subject).not_to be_valid
          end
        end
      end
    end

    context "title" do
      {
        string: ["foo", {"und" => ["foo"]}],
      }.each do |name, (input, output)|
        it name do
          subject.title = input
          expect(subject.title).to produce(output)
        end
      end
    end
  end

  describe RDF::Tabular::Schema do
    subject {described_class.new({}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    specify {is_expected.to be_valid}
    it_behaves_like("inherited properties")
    it_behaves_like("common properties")
    its(:type) {is_expected.to eql :Schema}

    describe "columns" do
      let(:column) {{"name" => "foo"}}
      subject {described_class.new({"columns" => []}, base: RDF::URI("http://example.org/base"), debug: @debug)}
      its(:errors) {is_expected.to be_empty}

      its(:type) {is_expected.to eql :Schema}

      it "allows a valid column" do
        v = described_class.new({"columns" => [column]}, base: RDF::URI("http://example.org/base"), debug: @debug)
        expect(v.errors).to be_empty
      end

      it "is invalid with an invalid column" do
        v = described_class.new({"columns" => [{"name" => "_invalid"}]}, base: RDF::URI("http://example.org/base"), debug: @debug)
        expect(v.errors).not_to be_empty
      end

      it "is invalid with an non-unique columns" do
        v = described_class.new({"columns" => [column, column]}, base: RDF::URI("http://example.org/base"), debug: @debug)
        expect(v.errors).not_to be_empty
      end
    end

    describe "primaryKey" do
      let(:column) {{"name" => "foo"}}
      let(:column2) {{"name" => "bar"}}
      subject {described_class.new({"columns" => [column], "primaryKey" => column["name"]}, base: RDF::URI("http://example.org/base"), debug: @debug)}
      specify {is_expected.to be_valid}

      its(:type) {is_expected.to eql :Schema}

      it "is invalid if referenced column does not exist" do
        subject[:columns] = []
        expect(subject).not_to be_valid
      end

      it "is valid with multiple names" do
        v = described_class.new({
          "columns" => [column, column2],
          "primaryKey" => [column["name"], column2["name"]]},
          base: RDF::URI("http://example.org/base"),
          debug: @debug)
        expect(v).to be_valid
      end

      it "is invalid with multiple names if any column missing" do
        v = described_class.new({
          "columns" => [column],
          "primaryKey" => [column["name"], column2["name"]]},
          base: RDF::URI("http://example.org/base",
          debug: @debug))
        expect(v).not_to be_valid
      end
    end

    describe "foreignKeys" do
      it "FIXME"
    end
  end

  describe RDF::Tabular::Transformation do
    let(:targetFormat) {"http://example.org/targetFormat"}
    let(:scriptFormat) {"http://example.org/scriptFormat"}
    subject {described_class.new({"targetFormat" => targetFormat, "scriptFormat" => scriptFormat}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    specify {is_expected.to be_valid}
    it_behaves_like("inherited properties", false)
    it_behaves_like("common properties")
    its(:type) {is_expected.to eql :Transformation}

    it "FIXME"

    context "title" do
      {
        string: ["foo", {"und" => ["foo"]}],
      }.each do |name, (input, output)|
        it name do
          subject.title = input
          expect(subject.title).to produce(output)
        end
      end
    end
  end

  describe RDF::Tabular::Dialect do
    subject {described_class.new({}, debug: @debug)}
    specify {is_expected.to be_valid}
    it_behaves_like("inherited properties", false)
    it_behaves_like("common properties", false)
    its(:type) {is_expected.to eql :Dialect}

    described_class.const_get(:DIALECT_DEFAULTS).each do |p, v|
      context "#{p}" do
        it "retrieves #{v.inspect} by default" do
          expect(subject.send(p)).to eql v
        end

        it "retrieves set value" do
          subject[p] = "foo"
          expect(subject.send(p)).to eql "foo"
        end
      end
    end
  end

  describe RDF::Tabular::Table do
    subject {described_class.new({"url" => "http://example.org/table.csv"}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    specify {is_expected.to be_valid}      
    it_behaves_like("inherited properties")
    it_behaves_like("common properties")
    its(:type) {is_expected.to eql :Table}

    it "FIXME"
  end

  describe RDF::Tabular::TableGroup do
    let(:table) {{"url" => "http://example.org/table.csv"}}
    subject {described_class.new({"resources" => [table]}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    specify {is_expected.to be_valid}
    
    it_behaves_like("inherited properties")
    it_behaves_like("common properties")
    its(:type) {is_expected.to eql :TableGroup}

    it "FIXME"
  end

  context "parses example metadata" do
    Dir.glob(File.expand_path("../data/*.json", __FILE__)).each do |filename|
      next if filename =~ /-(atd|standard|minimal).json/
      context filename do
        subject {RDF::Tabular::Metadata.open(filename)}
        its(:errors) {is_expected.to be_empty}
      end
    end
  end

  context "parses invalid metadata" do
    Dir.glob(File.expand_path("../invalid_data/*.json", __FILE__)).each do |filename|
      context filename do
        subject {RDF::Tabular::Metadata.open(filename)}
        File.foreach(filename.sub(".json", "-errors.txt")) do |err|
          its(:errors) {is_expected.to include(err)}
        end
      end
    end
  end

  context "object properties" do
    let(:table) {{"url" => "http://example.org/table.csv", "@type" => "Table"}}
    it "loads referenced schema" do
      table[:tableSchema] = "http://example.org/schema"
      expect(described_class).to receive(:open).with(table[:tableSchema], kind_of(Hash)).and_return('{"@type": "Schema"}')
      described_class.new(table, base: RDF::URI("http://example.org/base"), debug: @debug)
    end
    it "loads referenced dialect" do
      table[:dialect] = "http://example.org/dialect"
      expect(described_class).to receive(:open).with(table[:dialect], kind_of(Hash)).and_return('{"@type": "Dialect"}')
      described_class.new(table, base: RDF::URI("http://example.org/base"), debug: @debug)
    end
  end

  context "inherited properties" do
    let(:table) {{"url" => "http://example.org/table.csv", "tableSchema" => {"@type" => "Schema"}, "@type" => "Table"}}
    subject {described_class.new(table, base: RDF::URI("http://example.org/base"), debug: @debug)}

    it "inherits properties from parent" do
      subject.lang = "en"
      expect(subject.tableSchema.lang).to eql "en" 
    end

    it "overrides properties in parent" do
      subject.lang = "en"
      subject.tableSchema.lang = "de"
      expect(subject.tableSchema.lang).to eql "de" 
    end
  end

  describe ".open" do
    context "validates example metadata" do
      Dir.glob(File.expand_path("../data/*.json", __FILE__)).each do |filename|
        next if filename =~ /-(atd|standard|minimal).json/
        context filename do
          specify do
            md = RDF::Tabular::Metadata.open(filename, debug: @debug)
            expect(md.errors).to produce([], @debug)
          end
        end
      end
    end
  end

  describe ".from_input" do
    it "FIXME"
  end

  describe ".new" do
    context "intuits subclass" do
      {
        ":type TableGroup" => [{}, {type: :TableGroup}, RDF::Tabular::TableGroup],
        ":type Table" => [{}, {type: :Table}, RDF::Tabular::Table],
        ":type Transformation" => [{}, {type: :Transformation}, RDF::Tabular::Transformation],
        ":type Schema" => [{}, {type: :Schema}, RDF::Tabular::Schema],
        ":type Column" => [{}, {type: :Column}, RDF::Tabular::Column],
        ":type Dialect" => [{}, {type: :Dialect}, RDF::Tabular::Dialect],
        "@type TableGroup" => [{"@type" => "TableGroup"}, RDF::Tabular::TableGroup],
        "@type Table" => [{"@type" => "Table"}, RDF::Tabular::Table],
        "@type Transformation" => [{"@type" => "Transformation"}, RDF::Tabular::Transformation],
        "@type Schema" => [{"@type" => "Schema"}, RDF::Tabular::Schema],
        "@type Column" => [{"@type" => "Column"}, RDF::Tabular::Column],
        "@type Dialect" => [{"@type" => "Dialect"}, RDF::Tabular::Dialect],
        "resources TableGroup" => [{"resources" => []}, RDF::Tabular::TableGroup],
        "dialect Table" => [{"dialect" => {}}, RDF::Tabular::Table],
        "tableSchema Table" => [{"tableSchema" => {}}, RDF::Tabular::Table],
        "transformations Table" => [{"transformations" => []}, RDF::Tabular::Table],
        "targetFormat Transformation" => [{"targetFormat" => "foo"}, RDF::Tabular::Transformation],
        "scriptFormat Transformation" => [{"scriptFormat" => "foo"}, RDF::Tabular::Transformation],
        "source Transformation" => [{"source" => "foo"}, RDF::Tabular::Transformation],
        "columns Schema" => [{"columns" => []}, RDF::Tabular::Schema],
        "primaryKey Schema" => [{"primaryKey" => "foo"}, RDF::Tabular::Schema],
        "foreignKeys Schema" => [{"foreignKeys" => []}, RDF::Tabular::Schema],
        "urlTemplate Schema" => [{"urlTemplate" => "foo"}, RDF::Tabular::Schema],
        "commentPrefix Dialect" => [{"commentPrefix" => "#"}, RDF::Tabular::Dialect],
        "delimiter Dialect" => [{"delimiter" => ","}, RDF::Tabular::Dialect],
        "doubleQuote Dialect" => [{"doubleQuote" => true}, RDF::Tabular::Dialect],
        "encoding Dialect" => [{"encoding" => "utf-8"}, RDF::Tabular::Dialect],
        "header Dialect" => [{"header" => true}, RDF::Tabular::Dialect],
        "headerColumnCount Dialect" => [{"headerColumnCount" => 0}, RDF::Tabular::Dialect],
        "headerRowCount Dialect" => [{"headerRowCount" => 1}, RDF::Tabular::Dialect],
        "lineTerminator Dialect" => [{"lineTerminator" => "\r\n"}, RDF::Tabular::Dialect],
        "quoteChar Dialect" => [{"quoteChar" => "\""}, RDF::Tabular::Dialect],
        "skipBlankRows Dialect" => [{"skipBlankRows" => true}, RDF::Tabular::Dialect],
        "skipColumns Dialect" => [{"skipColumns" => 0}, RDF::Tabular::Dialect],
        "skipInitialSpace Dialect" => [{"skipInitialSpace" => "start"}, RDF::Tabular::Dialect],
        "skipRows Dialect" => [{"skipRows" => 1}, RDF::Tabular::Dialect],
        "trim Dialect" => [{"trim" => true}, RDF::Tabular::Dialect],
      }.each do |name, args|
        it name do
          klass = args.pop
          expect(described_class.new(*args)).to be_a(klass)
        end
      end
    end
  end

  describe "#embedded_metadata" do
    subject {described_class.new({"@type" => "Table"}, base: RDF::URI("http://example.org/base"), debug: @debug)}
    {
      "with defaults" => {
        input: "https://example.org/countries.csv",
        result: %({
          "@context": "http://www.w3.org/ns/csvw",
          "@type": "Table",
          "url": "https://example.org/countries.csv",
          "tableSchema": {
            "@type": "Schema",
            "columns": [
              {"title": {"und": ["countryCode"]}},
              {"title": {"und": ["latitude"]}},
              {"title": {"und": ["longitude"]}},
              {"title": {"und": ["name"]}}
            ]
          }
        })
      },
      "with skipRows" => {
        input: "https://example.org/countries.csv",
        metadata: %({
          "@type": "Table",
          "dialect": {"skipRows": 1}
        }),
        result: %({
          "@context": "http://www.w3.org/ns/csvw",
          "@type": "Table",
          "url": "https://example.org/countries.csv",
          "tableSchema": {
            "@type": "Schema",
            "columns": [
              {"title": {"und": ["AD"]}},
              {"title": {"und": ["42.546245"]}},
              {"title": {"und": ["1.601554"]}},
              {"title": {"und": ["Andorra"]}}
            ]
          },
          "notes": ["countryCode,latitude,longitude,name"]
        })
      },
      "with @language" => {
        input: "https://example.org/tree-ops.csv",
        metadata: %({
          "@context": {"@language": "en"},
          "@type": "Table"
        }),
        result: %({
          "@context": "http://www.w3.org/ns/csvw",
          "@type": "Table",
          "url": "https://example.org/tree-ops.csv",
          "tableSchema": {
            "@type": "Schema",
            "columns": [
              {"title": {"und": ["GID"]}},
              {"title": {"und": ["On Street"]}},
              {"title": {"und": ["Species"]}},
              {"title": {"und": ["Trim Cycle"]}},
              {"title": {"und": ["Inventory Date"]}}
            ]
          }
        })
      },
    }.each do |name, props|
      it name do
        metadata = if props[:metadata]
          described_class.new(JSON.parse(props[:metadata]), base: RDF::URI("http://example.org/base"), debug: @debug)
        end

        metadata = metadata ? subject.merge(metadata).resources.first : subject
        result = metadata.embedded_metadata(props[:input])
        expect(::JSON.parse(result.to_json(JSON_STATE))).to produce(::JSON.parse(props[:result]), @debug)
      end
    end
  end

  describe "#each_row" do
    subject {
      described_class.new(JSON.parse(%({
        "url": "https://example.org/countries.csv",
        "@type": "Table",
        "tableSchema": {
          "@type": "Schema",
          "columns": [{
            "name": "countryCode",
            "title": "countryCode",
            "propertyUrl": "https://example.org/countries.csv#countryCode"
          }, {
            "name": "latitude",
            "title": "latitude",
            "propertyUrl": "https://example.org/countries.csv#latitude"
          }, {
            "name": "longitude",
            "title": "longitude",
            "propertyUrl": "https://example.org/countries.csv#longitude"
          }, {
            "name": "name",
            "title": "name",
            "propertyUrl": "https://example.org/countries.csv#name"
          }]
        }
      })), base: RDF::URI("http://example.org/base"), debug: @debug)
    }
    let(:input) {RDF::Util::File.open_file("https://example.org/countries.csv")}

    specify {expect {|b| subject.each_row(input, &b)}.to yield_control.exactly(3)}

    it "returns consecutive row numbers" do
      nums = subject.to_enum(:each_row, input).map(&:number)
      expect(nums).to eql([1, 2, 3])
    end

    it "returns nil resources" do
      resources = subject.to_enum(:each_row, input).map(&:resource)
      expect(resources).to include(nil, nil, nil, nil)
    end

    it "returns cells" do
      subject.each_row(input) do |row|
        expect(row).to be_a(RDF::Tabular::Row)
        expect(row.values.length).to eql 4
        expect(row.values.map(&:class).compact).to include(RDF::Tabular::Row::Cell)
      end
    end

    it "has expected aboutUrls" do
      subject.each_row(input) do |row|
        expect(row.values[0].aboutUrl).to eql row.resource
        expect(row.values[1].aboutUrl).to eql row.resource
        expect(row.values[2].aboutUrl).to eql row.resource
        expect(row.values[3].aboutUrl).to eql row.resource
      end
    end

    it "has expected propertyUrls" do
      subject.each_row(input) do |row|
        expect(row.values[0].propertyUrl).to eq "https://example.org/countries.csv#countryCode"
        expect(row.values[1].propertyUrl).to eq "https://example.org/countries.csv#latitude"
        expect(row.values[2].propertyUrl).to eq "https://example.org/countries.csv#longitude"
        expect(row.values[3].propertyUrl).to eq "https://example.org/countries.csv#name"
      end
    end

    it "has expected valueUrls" do
      subject.each_row(input) do |row|
        expect(row.values[0].valueUrl).to be_nil
        expect(row.values[1].valueUrl).to be_nil
        expect(row.values[2].valueUrl).to be_nil
        expect(row.values[3].valueUrl).to be_nil
      end
    end

    it "has expected values" do
      rows = subject.to_enum(:each_row, input).to_a
      expect(rows[0].values.map(&:to_s)).to produce(%w(AD 42.546245 1.601554 Andorra), @debug)
      expect(rows[1].values.map(&:to_s)).to produce((%w(AE 23.424076 53.847818) << "United Arab Emirates"), @debug)
      expect(rows[2].values.map(&:to_s)).to produce(%w(AF 33.93911 67.709953 Afghanistan), @debug)
    end

    context "URL expansion" do
      subject {
        described_class.new(JSON.parse(%({
          "url": "https://example.org/countries.csv",
          "tableSchema": {
            "columns": [
              {"title": "addressCountry"},
              {"title": "latitude"},
              {"title": "longitude"},
              {"title": "name"}
            ]
          }
        })), base: RDF::URI("http://example.org/base"), debug: @debug)
      }
      let(:input) {RDF::Util::File.open_file("https://example.org/countries.csv")}

      {
        "default title" => {
          aboutUrl: [RDF::Node, RDF::Node, RDF::Node, RDF::Node],
          propertyUrl: %w(#addressCountry #latitude #longitude #name),
          valueUrl: [nil, nil, nil, nil],
          md: {"url" => "https://example.org/countries.csv", "tableSchema" => {"columns" => []}}
        },
        "schema transformations" => {
          aboutUrl: %w(#addressCountry #latitude #longitude #name),
          propertyUrl: %w(?_name=addressCountry ?_name=latitude ?_name=longitude ?_name=name),
          valueUrl: %w(addressCountry latitude longitude name),
          md: {
            "url" => "https://example.org/countries.csv",
            "tableSchema" => {
              "aboutUrl" => "{#_name}",
              "propertyUrl" => '{?_name}',
              "valueUrl" => '{_name}',
              "columns" => []
            }
          }
        },
        "PNames" => {
          aboutUrl: [RDF::SCHEMA.addressCountry, RDF::SCHEMA.latitude, RDF::SCHEMA.longitude, RDF::SCHEMA.name],
          propertyUrl: [RDF::SCHEMA.addressCountry, RDF::SCHEMA.latitude, RDF::SCHEMA.longitude, RDF::SCHEMA.name],
          valueUrl: [RDF::SCHEMA.addressCountry, RDF::SCHEMA.latitude, RDF::SCHEMA.longitude, RDF::SCHEMA.name],
          md: {
            "url" => "https://example.org/countries.csv",
            "tableSchema" => {
              "aboutUrl" => 'http://schema.org/{_name}',
              "propertyUrl" => 'schema:{_name}',
              "valueUrl" => 'schema:{_name}',
              "columns" => []
            }
          }
        },
      }.each do |name, props|
        context name do
          let(:md) {RDF::Tabular::Table.new(props[:md]).merge(subject).resources.first}
          let(:cells) {md.to_enum(:each_row, input).to_a.first.values}
          let(:aboutUrls) {props[:aboutUrl].map {|u| u.is_a?(String) ? md.url.join(u) : u}}
          let(:propertyUrls) {props[:propertyUrl].map {|u| u.is_a?(String) ? md.url.join(u) : u}}
          let(:valueUrls) {props[:valueUrl].map {|u| u.is_a?(String) ? md.url.join(u) : u}}
          it "aboutUrl is #{props[:aboutUrl]}" do
            if aboutUrls.first == RDF::Node
              expect(cells.map(&:aboutUrl)).to all(be_nil)
            else
              expect(cells.map(&:aboutUrl)).to include(*aboutUrls)
            end
          end
          it "propertyUrl is #{props[:propertyUrl]}" do
            expect(cells.map(&:propertyUrl)).to include(*propertyUrls)
          end
          it "valueUrl is #{props[:valueUrl]}" do
            expect(cells.map(&:valueUrl)).to include(*valueUrls)
          end
        end
      end
    end
    it "expands aboutUrl in cells"

    context "variations" do
      {
        "skipRows" => {dialect: {skipRows: 1}},
        "headerRowCount" => {dialect: {headerRowCount: 0}},
        "skipRows + headerRowCount" => {dialect: {skipRows: 1, headerRowCount: 0}},
        "skipColumns" => {dialect: {skipColumns: 1}},
        "headerColumnCount" => {dialect: {headerColumnCount: 0}},
        "skipColumns + headerColumnCount" => {dialect: {skipColumns: 1, headerColumnCount: 0}},
      }.each do |name, props|
        context name do
          subject {
            raw = JSON.parse(%({
              "url": "https://example.org/countries.csv",
              "@type": "Table",
              "tableSchema": {
                "@type": "Schema",
                "columns": [{
                  "name": "countryCode",
                  "title": "countryCode",
                  "propertyUrl": "https://example.org/countries.csv#countryCode"
                }, {
                  "name": "latitude",
                  "title": "latitude",
                  "propertyUrl": "https://example.org/countries.csv#latitude"
                }, {
                  "name": "longitude",
                  "title": "longitude",
                  "propertyUrl": "https://example.org/countries.csv#longitude"
                }, {
                  "name": "name",
                  "title": "name",
                  "propertyUrl": "https://example.org/countries.csv#name"
                }]
              }
            }))
            raw["dialect"] = props[:dialect]
            described_class.new(raw, base: RDF::URI("http://example.org/base"), debug: @debug)
          }
          let(:rows) {subject.to_enum(:each_row, input).to_a}
          let(:rowOffset) {props[:dialect].fetch(:skipRows, 0) + props[:dialect].fetch(:headerRowCount, 1)}
          let(:columnOffset) {props[:dialect].fetch(:skipColumns, 0) + props[:dialect].fetch(:headerColumnCount, 0)}
          it "has expected number attributes" do
            nums = [1, 2, 3, 4]
            nums = nums.first(nums.length - rowOffset)
            expect(rows.map(&:number)).to eql nums
          end
          it "has expected sourceNumber attributes" do
            nums = [1, 2, 3, 4].map {|n| n + rowOffset}
            nums = nums.first(nums.length - rowOffset)
            expect(rows.map(&:sourceNumber)).to eql nums
          end
          it "has expected column.number attributes" do
            nums = [1, 2, 3, 4]
            nums = nums.first(nums.length - columnOffset)
            expect(rows.first.values.map {|c| c.column.number}).to eql nums
          end
          it "has expected column.sourceNumber attributes" do
            nums = [1, 2, 3, 4].map {|n| n + columnOffset}
            nums = nums.first(nums.length - columnOffset)
            expect(rows.first.values.map {|c| c.column.sourceNumber}).to eql nums
          end
        end
      end
    end

    context "datatypes" do
      {
        # Strings
        "string with no constraints" => {base: "string", value: "foo", result: "foo"},
        "string with matching length" => {base: "string", value: "foo", length: 3, result: "foo"},
        "string with wrong length" => {
          base: "string",
          value: "foo",
          length: 4,
          errors: ["foo does not have length 4"]
        },
        "string with wrong maxLength" => {
          base: "string",
          value: "foo",
          maxLength: 2,
          errors: ["foo does not have length <= 2"]
        },
        "string with wrong minLength" => {
          base: "string",
          value: "foo",
          minLength: 4,
          errors: ["foo does not have length >= 4"]
        },

        # Numbers
        "decimal with no constraints" => {
          base: "decimal",
          value: "4"
        },
        "decimal with matching pattern" => {
          base: "decimal",
          pattern: '\d{3}',
          value: "123"
        },
        "decimal with wrong pattern" => {
          base: "decimal",
          pattern: '\d{4}',
          value: "123",
          errors: [/123 does not match pattern/]
        },
        "decimal with implicit groupChar" => {
          base: "decimal",
          value: %("123,456.789"),
          result: "123456.789"
        },
        "decimal with explicit groupChar" => {
          base: "decimal",
          groupChar: ";",
          value: "123;456.789",
          result: "123456.789"
        },
        "decimal with repeated groupChar" => {
          base: "decimal",
          groupChar: ";",
          value: "123;;456.789",
          result: "123;;456.789",
          errors: [/has repeating/]
        },
        "decimal with explicit decimalChar" => {
          base: "decimal",
          decimalChar: ";",
          value: "123456;789",
          result: "123456.789"
        },
        "invalid decimal" => {
          base: "decimal",
          value: "123456.789e10",
          result: "123456.789e10",
          errors: ["123456.789e10 is not a valid decimal"]
        },
        "decimal with percent" => {
          base: "decimal",
          value: "123456.789%",
          result: "1234.56789"
        },
        "decimal with per-mille" => {
          base: "decimal",
          value: "123456.789‰",
          result: "123.456789"
        },
        "valid integer" => {base: "integer", value: "1234"},
        "invalid integer" => {base: "integer", value: "1234.56", errors: ["1234.56 is not a valid integer"]},
        "valid long" => {base: "long", value: "1234"},
        "invalid long" => {base: "long", value: "1234.56", errors: ["1234.56 is not a valid long"]},
        "valid short" => {base: "short", value: "1234"},
        "invalid short" => {base: "short", value: "1234.56", errors: ["1234.56 is not a valid short"]},
        "valid byte" => {base: "byte", value: "123"},
        "invalid byte" => {base: "byte", value: "1234", errors: ["1234 is not a valid byte"]},
        "valid unsignedLong" => {base: "unsignedLong", value: "1234"},
        "invalid unsignedLong" => {base: "unsignedLong", value: "-1234", errors: ["-1234 is not a valid unsignedLong"]},
        "valid unsignedShort" => {base: "unsignedShort", value: "1234"},
        "invalid unsignedShort" => {base: "unsignedShort", value: "-1234", errors: ["-1234 is not a valid unsignedShort"]},
        "valid unsignedByte" => {base: "unsignedByte", value: "123"},
        "invalid unsignedByte" => {base: "unsignedByte", value: "-123", errors: ["-123 is not a valid unsignedByte"]},
        "valid positiveInteger" => {base: "positiveInteger", value: "123"},
        "invalid positiveInteger" => {base: "positiveInteger", value: "-123", errors: ["-123 is not a valid positiveInteger"]},
        "valid negativeInteger" => {base: "negativeInteger", value: "-123"},
        "invalid negativeInteger" => {base: "negativeInteger", value: "123", errors: ["123 is not a valid negativeInteger"]},
        "valid nonPositiveInteger" => {base: "nonPositiveInteger", value: "0"},
        "invalid nonPositiveInteger" => {base: "nonPositiveInteger", value: "1", errors: ["1 is not a valid nonPositiveInteger"]},
        "valid nonNegativeInteger" => {base: "nonNegativeInteger", value: "0"},
        "invalid nonNegativeInteger" => {base: "nonNegativeInteger", value: "-1", errors: ["-1 is not a valid nonNegativeInteger"]},
        "valid double" => {base: "double", value: "1234.456E789"},
        "invalid double" => {base: "double", value: "1z", errors: ["1z is not a valid double"]},
        "NaN double" => {base: "double", value: "NaN"},
        "INF double" => {base: "double", value: "INF"},
        "-INF double" => {base: "double", value: "-INF"},
        "valid float" => {base: "float", value: "1234.456E789"},
        "invalid float" => {base: "float", value: "1z", errors: ["1z is not a valid float"]},
        "NaN float" => {base: "float", value: "NaN"},
        "INF float" => {base: "float", value: "INF"},
        "-INF float" => {base: "float", value: "-INF"},

        # Booleans
        "valid boolean true" => {base: "boolean", value: "true"},
        "valid boolean false" => {base: "boolean", value: "false"},
        "valid boolean 1" => {base: "boolean", value: "1", result: "true"},
        "valid boolean 0" => {base: "boolean", value: "0", result: "false"},
        "valid boolean Y|N Y" => {base: "boolean", value: "Y", format: "Y|N", result: "true"},
        "valid boolean Y|N N" => {base: "boolean", value: "N", format: "Y|N", result: "false"},

        # Dates
        "validate date yyyy-MM-dd" => {base: "date", value: "2015-03-22", format: "yyyy-MM-dd", result: "2015-03-22"},
        "validate date yyyyMMdd" => {base: "date", value: "20150322", format: "yyyyMMdd", result: "2015-03-22"},
        "validate date dd-MM-yyyy" => {base: "date", value: "22-03-2015", format: "dd-MM-yyyy", result: "2015-03-22"},
        "validate date d-M-yyyy" => {base: "date", value: "22-3-2015", format: "d-M-yyyy", result: "2015-03-22"},
        "validate date MM-dd-yyyy" => {base: "date", value: "03-22-2015", format: "MM-dd-yyyy", result: "2015-03-22"},
        "validate date M/d/yyyy" => {base: "date", value: "3/22/2015", format: "M-d-yyyy", result: "2015-03-22"},
        "validate date dd/MM/yyyy" => {base: "date", value: "22/03/2015", format: "dd/MM/yyyy", result: "2015-03-22"},
        "validate date d/M/yyyy" => {base: "date", value: "22/3/2015", format: "d/M/yyyy", result: "2015-03-22"},
        "validate date MM/dd/yyyy" => {base: "date", value: "03/22/2015", format: "MM/dd/yyyy", result: "2015-03-22"},
        "validate date M/d/yyyy" => {base: "date", value: "3/22/2015", format: "M/d/yyyy", result: "2015-03-22"},
        "validate date dd.MM.yyyy" => {base: "date", value: "22.03.2015", format: "dd.MM.yyyy", result: "2015-03-22"},
        "validate date d.M.yyyy" => {base: "date", value: "22.3.2015", format: "d.M.yyyy", result: "2015-03-22"},
        "validate date MM.dd.yyyy" => {base: "date", value: "03.22.2015", format: "MM.dd.yyyy", result: "2015-03-22"},
        "validate date M.d.yyyy" => {base: "date", value: "3.22.2015", format: "M.d.yyyy", result: "2015-03-22"},

        # Times
        "valid time HH:mm:ss" => {base: "time", value: "15:02:37", format: "HH:mm:ss", result: "15:02:37"},
        "valid time HHmmss" => {base: "time", value: "150237", format: "HHmmss", result: "15:02:37"},
        "valid time HH:mm" => {base: "time", value: "15:02", format: "HH:mm", result: "15:02:00"},
        "valid time HHmm" => {base: "time", value: "1502", format: "HHmm", result: "15:02:00"},

        # DateTimes
        "valid dateTime yyyy-MM-ddTHH:mm:ss" => {base: "dateTime", value: "2015-03-15T15:02:37", format: "yyyy-MM-ddTHH:mm:ss", result: "2015-03-15T15:02:37"},
        "valid dateTime yyyy-MM-dd HH:mm:ss" => {base: "dateTime", value: "2015-03-15 15:02:37", format: "yyyy-MM-dd HH:mm:ss", result: "2015-03-15T15:02:37"},
        "valid dateTime yyyyMMdd HHmmss"   => {base: "dateTime", value: "20150315 150237",   format: "yyyyMMdd HHmmss",   result: "2015-03-15T15:02:37"},
        "valid dateTime dd-MM-yyyy HH:mm" => {base: "dateTime", value: "15-03-2015 15:02", format: "dd-MM-yyyy HH:mm", result: "2015-03-15T15:02:00"},
        "valid dateTime d-M-yyyy HHmm"   => {base: "dateTime", value: "15-3-2015 1502",  format: "d-M-yyyy HHmm",   result: "2015-03-15T15:02:00"},
        "valid dateTimeStamp d-M-yyyy HHmm X"   => {base: "dateTimeStamp", value: "15-3-2015 1502 Z",  format: "d-M-yyyy HHmm X",   result: "2015-03-15T15:02:00Z"},

        # Timezones
        "valid w/TZ yyyy-MM-ddX" => {base: "date", value: "2015-03-22Z", format: "yyyy-MM-ddX", result: "2015-03-22Z"},
        "valid w/TZ dd.MM.yyyy XXXXX" => {base: "date", value: "22.03.2015 Z", format: "dd.MM.yyyy XXXXX", result: "2015-03-22Z"},
        "valid w/TZ HH:mm:ssX" => {base: "time", value: "15:02:37-05:00", format: "HH:mm:ssX", result: "15:02:37-05:00"},
        "valid w/TZ HHmm XX" => {base: "time", value: "1502 +08:00", format: "HHmm XX", result: "15:02:00+08:00"},
        "valid w/TZ yyyy-MM-ddTHH:mm:ssXXX" => {base: "dateTime", value: "2015-03-15T15:02:37-05:00", format: "yyyy-MM-ddTHH:mm:ssXXX", result: "2015-03-15T15:02:37-05:00"},
        "valid w/TZ yyyy-MM-dd HH:mm:ss X" => {base: "dateTimeStamp", value: "2015-03-15 15:02:37 +08:00", format: "yyyy-MM-dd HH:mm:ss X", result: "2015-03-15T15:02:37+08:00"},
        "valid gDay" => {base: "gDay", value: "---31"},
        "valid gMonth" => {base: "gMonth", value: "--02"},
        "valid gMonthDay" => {base: "gMonthDay", value: "--02-21"},
        "valid gYear" => {base: "gYear", value: "9999"},
        "valid gYearMonth" => {base: "gYearMonth", value: "1999-05"},

        # Durations
        "valid duration PT130S"    => {base: "duration", value: "PT130S"},
        "valid duration PT130M"    => {base: "duration", value: "PT130M"},
        "valid duration PT130H"    => {base: "duration", value: "PT130H"},
        "valid duration P130D"     => {base: "duration", value: "P130D"},
        "valid duration P130M"     => {base: "duration", value: "P130M"},
        "valid duration P130Y"     => {base: "duration", value: "P130Y"},
        "valid duration PT2M10S"   => {base: "duration", value: "PT2M10S"},
        "valid duration P0Y20M0D"  => {base: "duration", value: "P0Y20M0D"},
        "valid duration -P60D"     => {base: "duration", value: "-P60D"},
        "valid dayTimeDuration P1DT2H"    => {base: "dayTimeDuration", value: "P1DT2H"},
        "valid yearMonthDuration P0Y20M"  => {base: "yearMonthDuration", value: "P0Y20M"},

        # Other datatypes
        "valid anyAtomicType" => {base: "anyAtomicType", value: "some thing", result: RDF::Literal("some thing", datatype: RDF::XSD.anyAtomicType)},
        "valid anyURI" => {base: "anyURI", value: "http://example.com/", result: RDF::Literal("http://example.com/", datatype: RDF::XSD.anyURI)},
        "valid base64Binary" => {base: "base64Binary", value: "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g", result: RDF::Literal("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g", datatype: RDF::XSD.base64Binary)},
        "valid hexBinary" => {base: "hexBinary", value: "0FB7", result: RDF::Literal("0FB7", datatype: RDF::XSD.hexBinary)},
        "valid QName" => {base: "QName", value: "foo:bar", result: RDF::Literal("foo:bar", datatype: RDF::XSD.QName)},
        "valid normalizedString" => {base: "normalizedString", value: "some thing", result: RDF::Literal("some thing", datatype: RDF::XSD.normalizedString)},
        "valid token" => {base: "token", value: "some thing", result: RDF::Literal("some thing", datatype: RDF::XSD.token)},
        "valid language" => {base: "lang", value: "en", result: RDF::Literal("en", datatype: RDF::XSD.language)},
        "valid Name" => {base: "Name", value: "someThing", result: RDF::Literal("someThing", datatype: RDF::XSD.Name)},
        "valid NMTOKEN" => {base: "NMTOKEN", value: "someThing", result: RDF::Literal("someThing", datatype: RDF::XSD.NMTOKEN)},

        # Unsupported datatypes
        "anyType not allowed" => {base: "anyType", value: "some thing", errors: [/unsupported datatype/]},
        "anySimpleType not allowed" => {base: "anySimpleType", value: "some thing", errors: [/unsupported datatype/]},
        "ENTITIES not allowed" => {base: "ENTITIES", value: "some thing", errors: [/unsupported datatype/]},
        "IDREFS not allowed" => {base: "IDREFS", value: "some thing", errors: [/unsupported datatype/]},
        "NMTOKENS not allowed" => {base: "NMTOKENS", value: "some thing", errors: [/unsupported datatype/]},
        "ENTITY not allowed" => {base: "ENTITY", value: "something", errors: [/unsupported datatype/]},
        "ID not allowed" => {base: "ID", value: "something", errors: [/unsupported datatype/]},
        "IDREF not allowed" => {base: "IDREF", value: "something", errors: [/unsupported datatype/]},
        "NOTATION not allowed" => {base: "NOTATION", value: "some:thing", errors: [/unsupported datatype/]},

        # Aliases
        "number is alias for double" => {base: "number", value: "1234.456E789", result: RDF::Literal("1234.456E789", datatype: RDF::XSD.double)},
        "binary is alias for base64Binary" => {base: "binary", value: "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g", result: RDF::Literal("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g", datatype: RDF::XSD.base64Binary)},
        "datetime is alias for dateTime" => {base: "dateTime", value: "15-3-2015 1502",  format: "d-M-yyyy HHmm", result: RDF::Literal("2015-03-15T15:02:00", datatype: RDF::XSD.dateTime)},
        "any is alias for anyAtomicType" => {base: "any", value: "some thing", result: RDF::Literal("some thing", datatype: RDF::XSD.anyAtomicType)},
        "xml is alias for rdf:XMLLiteral" => {base: "xml", value: "<foo></foo>", result: RDF::Literal("<foo></foo>", datatype: RDF.XMLLiteral)},
        "html is alias for rdf:HTML" => {base: "html", value: "<foo></foo>", result: RDF::Literal("<foo></foo>", datatype: RDF.HTML)},
        #"json is alias for csvw:JSON" => {base: "json", value: %({""foo"": ""bar""}), result: RDF::Literal(%({"foo": "bar"}), datatype: RDF::Tabular::CSVW.json)},
      }.each do |name, props|
        context name do
          let(:value) {props[:value]}
          let(:result) {
            if props[:errors]
              RDF::Literal(props.fetch(:result, value))
            else
              RDF::Literal(props.fetch(:result, value), datatype: md.context.expand_iri(props[:base], vocab: true))
            end
          }
          let(:md) {
            RDF::Tabular::Table.new({
             url: "http://example.com/table.csv",
              dialect: {header: false},
              tableSchema: {
                columns: [{
                  name: "name",
                  datatype: [props.dup.delete_if {|k, v| [:value, :valid, :result].include?(k)}]
                }]
              }
            }, debug: @debug)
          }
          subject {md.to_enum(:each_row, "#{value}\n").to_a.first.values.first}

          if props[:errors]
            it {is_expected.not_to be_valid}
            it "has expected errors" do
              props[:errors].each do |e|
                expect(subject.errors.to_s).to match(e)
              end
            end
          else
            it {is_expected.to be_valid}
            it "has no errors" do
              expect(subject.errors).to be_empty
            end
          end

          specify {expect(subject.value).to eql result}
        end
      end
    end
  end

  describe "#common_properties" do
    describe "#normalize!" do
      {
        "string with no language" => [
          %({
            "dc:title": "foo"
          }),
          %({
            "@context": "http://www.w3.org/ns/csvw",
            "dc:title": {"@value": "foo"}
          })
        ],
        "string with language" => [
          %({
            "@context": {"@language": "en"},
            "dc:title": "foo"
          }),
          %({
            "@context": "http://www.w3.org/ns/csvw",
            "dc:title": {"@value": "foo", "@language": "en"}
          })
        ],
        "relative URL" => [
          %({
            "dc:source": {"@id": "foo"}
          }),
          %({
            "@context": "http://www.w3.org/ns/csvw",
            "dc:source": {"@id": "http://example.com/foo"}
          })
        ],
        "array of values" => [
          %({
            "@context": {"@language": "en"},
            "dc:title": [
              "foo",
              {"@value": "bar"},
              {"@value": "baz", "@language": "de"},
              1,
              true,
              {"@value": 1},
              {"@value": true},
              {"@value": "1", "@type": "xsd:integer"},
              {"@id": "foo"}
            ]
          }),
          %({
            "@context": "http://www.w3.org/ns/csvw",
            "dc:title": [
              {"@value": "foo", "@language": "en"},
              {"@value": "bar"},
              {"@value": "baz", "@language": "de"},
              1,
              true,
              {"@value": 1},
              {"@value": true},
              {"@value": "1", "@type": "xsd:integer"},
              {"@id": "http://example.com/foo"}
            ]
          })
        ],
      }.each do |name, (input, result)|
        it name do
          a = RDF::Tabular::Table.new(input, base: "http://example.com/A")
          b = RDF::Tabular::Table.new(result, base: "http://example.com/A")
          expect(a.normalize!).to eq b
        end
      end
    end

    context "validation" do
    end

    context "transformation" do
    end
  end

  describe "#merge" do
    {
      "two tables with same id" => {
        A: %({
          "@type": "Table",
          "url": "http://example.org/table"
        }),
        B: [%({
          "@type": "Table",
          "url": "http://example.org/table"
        })],
        R: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table"
          }],
          "@context": "http://www.w3.org/ns/csvw"
        })
      },
      "two tables with different id" => {
        A: %({
          "@type": "Table",
          "url": "http://example.org/table1"
        }),
        B: [%({
          "@type": "Table",
          "url": "http://example.org/table2"
        })],
        R: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }, {
            "@type": "Table",
            "url": "http://example.org/table2"
          }],
          "@context": "http://www.w3.org/ns/csvw"
        })
      },
      "table and table-group" => {
        A: %({
          "@type": "Table",
          "url": "http://example.org/table1"
        }),
        B: [%({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table2"
          }]
        })],
        R: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }, {
            "@type": "Table",
            "url": "http://example.org/table2"
          }],
          "@context": "http://www.w3.org/ns/csvw"
        })
      },
      "table-group and table" => {
        A: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }]
        }),
        B: [%({
          "@type": "Table",
          "url": "http://example.org/table2"
        })],
        R: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }, {
            "@type": "Table",
            "url": "http://example.org/table2"
          }],
          "@context": "http://www.w3.org/ns/csvw"
        })
      },
      "table-group and two tables" => {
        A: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }]
        }),
        B: [%({
          "@type": "Table",
          "url": "http://example.org/table2",
          "dc:label": "foo"
        }), %({
          "@type": "Table",
          "url": "http://example.org/table2",
          "dc:label": "bar"
        })],
        R: %({
          "@type": "TableGroup",
          "resources": [{
            "@type": "Table",
            "url": "http://example.org/table1"
          }, {
            "@type": "Table",
            "url": "http://example.org/table2",
            "dc:label": {"@value": "foo"}
          }],
          "@context": "http://www.w3.org/ns/csvw"
        })
      },
    }.each do |name, props|
      it name do
        a = described_class.new(::JSON.parse(props[:A]))
        b = props[:B].map {|md| described_class.new(::JSON.parse(md))}
        r = described_class.new(::JSON.parse(props[:R]))
        expect(a.merge(*b)).to produce(r, @debug)
      end
    end

    %w(Transformation Schema Transformation Column Dialect).each do |t|
      it "does not merge into a #{t}" do
        a = described_class.new({}, type: t.to_sym)
        b = described_class.new({}, type: :TableGroup)
        expect {a.merge(b)}.to raise_error
      end

      it "does not merge from a #{t}" do
        a = described_class.new({}, type: :TableGroup)
        b = described_class.new({}, type: t.to_sym)
        expect {a.merge(b)}.to raise_error
      end
    end
  end

  describe "#merge!" do
    {
      "TableGroup with and without @id" => {
        A: %({"@id": "http://example.org/foo", "resources": [], "@type": "TableGroup"}),
        B: %({"resources": [], "@type": "TableGroup"}),
        R: %({"@id": "http://example.org/foo", "resources": [], "@type": "TableGroup"})
      },
      "TableGroup with and without @type" => {
        A: %({"resources": []}),
        B: %({"resources": [], "@type": "TableGroup"}),
        R: %({"resources": [], "@type": "TableGroup"})
      },
      "TableGroup with matching resources" => {
        A: %({"resources": [{"url": "http://example.org/foo", "dc:title": "foo"}]}),
        B: %({"resources": [{"url": "http://example.org/foo", "dc:description": "bar"}]}),
        R: %({"resources": [{
          "url": "http://example.org/foo",
          "dc:title": {"@value": "foo"},
          "dc:description": {"@value": "bar"}
        }]})
      },
      "TableGroup with differing resources" => {
        A: %({"resources": [{"url": "http://example.org/foo", "dc:title": "foo"}]}),
        B: %({"resources": [{"url": "http://example.org/bar", "dc:description": "bar"}]}),
        R: %({
          "resources": [
            {"url": "http://example.org/foo", "dc:title": "foo"},
            {"url": "http://example.org/bar", "dc:description": "bar"}
          ]})
      },
      "Table with schemas always takes A" => {
        A: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {"columns": [{"name": "foo"}]}
        }),
        B: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {"columns": [{"name": "bar"}]}
        }),
        R: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {"columns": [{"name": "foo"}]}
        }),
      },
      "Table with tableDirection always takes A" => {
        A: %({"@type": "Table", "url": "http://example.com/foo", "tableDirection": "ltr"}),
        B: %({"@type": "Table", "url": "http://example.com/foo", "tableDirection": "rtl"}),
        R: %({"@type": "Table", "url": "http://example.com/foo", "tableDirection": "ltr"}),
      },
      "Table with dialect merges A and B" => {
        A: %({"@type": "Table", "url": "http://example.com/foo", "dialect": {"encoding": "utf-8"}}),
        B: %({"@type": "Table", "url": "http://example.com/foo", "dialect": {"skipRows": 0}}),
        R: %({"@type": "Table", "url": "http://example.com/foo", "dialect": {"encoding": "utf-8", "skipRows": 0}}),
      },
      "Table with equivalent transformations uses A" => {
        A: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/foo",
            "targetFormat": "http://example.com/target",
            "scriptFormat": "http://example.com/template",
            "source": "json"
          }]
        }),
        B: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/foo",
            "targetFormat": "http://example.com/target",
            "scriptFormat": "http://example.com/template",
            "source": "html"
          }]
        }),
        R: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/foo",
            "targetFormat": "http://example.com/target",
            "scriptFormat": "http://example.com/template",
            "source": "json"
          }]
        }),
      },
      "Table with differing transformations appends B to A" => {
        A: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/foo",
            "targetFormat": "http://example.com/target",
            "scriptFormat": "http://example.com/template"
          }]
        }),
        B: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/bar",
            "targetFormat": "http://example.com/targetb",
            "scriptFormat": "http://example.com/templateb"
          }]
        }),
        R: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "transformations": [{
            "url": "http://example.com/foo",
            "targetFormat": "http://example.com/target",
            "scriptFormat": "http://example.com/template"
          }, {
            "url": "http://example.com/bar",
            "targetFormat": "http://example.com/targetb",
            "scriptFormat": "http://example.com/templateb"
          }]
        }),
      },
      "Table with common properties keeps A" => {
        A: %({"@type": "Table", "url": "http://example.com/foo", "rdfs:label": "foo"}),
        B: %({"@type": "Table", "url": "http://example.com/foo", "rdfs:label": "bar"}),
        R: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "rdfs:label": {"@value": "foo"}
        }),
      },
      "Table with common properties in different languages keeps A" => {
        A: %({
          "@context": {"@language": "en"},
          "@type": "Table",
          "url": "http://example.com/foo",
          "rdfs:label": "foo"
        }),
        B: %({
          "@context": {"@language": "fr"},
          "@type": "Table",
          "url": "http://example.com/foo",
          "rdfs:label": "foo"
        }),
        R: %({
          "@context": "http://www.w3.org/ns/csvw",
          "@type": "Table",
          "url": "http://example.com/foo",
          "rdfs:label": {"@value": "foo", "@language": "en"}
        }),
      },
      "Table with different languages merges A and B" => {
        A: %({
          "@context": {"@language": "en"},
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {
            "columns": [{"title": "foo"}]
          }
        }),
        B: %({
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {
            "columns": [{"title": "foo"}]
          }
        }),
        R: %({
          "@context": "http://www.w3.org/ns/csvw",
          "@type": "Table",
          "url": "http://example.com/foo",
          "tableSchema": {
            "columns": [{"title": {"en": ["foo"]}}]
          }
        }),
      },
      "Schema with matching columns merges A and B" => {
        A: %({"@type": "Schema", "columns": [{"name": "foo", "required": true}]}),
        B: %({"@type": "Schema", "columns": [{"name": "foo", "required": false}]}),
        R: %({"@type": "Schema", "columns": [{"name": "foo", "required": true}]}),
      },
      "Schema with differing columns takes A" => {
        A: %({"@type": "Schema", "columns": [{"name": "foo"}]}),
        B: %({"@type": "Schema", "columns": [{"name": "bar"}]}),
        R: %({"@type": "Schema", "columns": [{"name": "foo"}]}),
      },
      "Schema with matching column titles" => {
        A: %({"@type": "Schema", "columns": [{"title": "Foo"}]}),
        B: %({"@type": "Schema", "columns": [{"name": "foo", "title": "Foo"}]}),
        R: %({"@type": "Schema", "columns": [{"name": "foo", "title": {"und": ["Foo"]}}]}),
      },
      "Schema with primaryKey always takes A" => {
        A: %({"@type": "Schema", "primaryKey": "foo"}),
        B: %({"@type": "Schema", "primaryKey": "bar"}),
        R: %({"@type": "Schema", "primaryKey": "foo"}),
      },
      "Schema with matching foreignKey uses A" => {
        A: %({"@type": "Schema", "columns": [{"name": "foo"}], "foreignKeys": [{"columns": "foo", "reference": {"columns": "foo"}}]}),
        B: %({"@type": "Schema", "columns": [{"name": "foo"}], "foreignKeys": [{"columns": "foo", "reference": {"columns": "foo"}}]}),
        R: %({"@type": "Schema", "columns": [{"name": "foo"}], "foreignKeys": [{"columns": "foo", "reference": {"columns": "foo"}}]}),
      },
      "Schema with differing foreignKey uses A and B" => {
        A: %({"@type": "Schema", "columns": [{"name": "foo"}, {"name": "bar"}], "foreignKeys": [{"columns": "foo", "reference": {"columns": "foo"}}]}),
        B: %({"@type": "Schema", "columns": [{"name": "foo"}, {"name": "bar"}], "foreignKeys": [{"columns": "bar", "reference": {"columns": "bar"}}]}),
        R: %({"@type": "Schema", "columns": [{"name": "foo"}, {"name": "bar"}], "foreignKeys": [{"columns": "foo", "reference": {"columns": "foo"}}, {"columns": "bar", "reference": {"columns": "bar"}}]}),
      },
      "Schema with urlTemplate always takes A" => {
        A: %({"@type": "Schema", "urlTemplate": "foo"}),
        B: %({"@type": "Schema", "urlTemplate": "bar"}),
        R: %({"@type": "Schema", "urlTemplate": "foo"}),
      },
    }.each do |name, props|
      it name do
        a = described_class.new(::JSON.parse(props[:A]), debug: @debug)
        b = described_class.new(::JSON.parse(props[:B]))
        r = described_class.new(::JSON.parse(props[:R]))
        m = a.merge!(b)
        expect(m).to produce(r, @debug)
        expect(a).to equal m
      end
    end

    %w(TableGroup Table Transformation Schema Transformation Column Dialect).each do |ta|
      %w(TableGroup Table Transformation Schema Transformation Column Dialect).each do |tb|
        next if ta == tb
        it "does not merge #{tb} into #{ta}" do
          a = described_class.new({}, type: ta.to_sym)
          b = described_class.new({}, type: tb.to_sym)
          expect {a.merge!(b)}.to raise_error
        end
      end
    end
  end
end
