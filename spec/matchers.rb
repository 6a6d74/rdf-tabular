require 'rdf/isomorphic'
require 'rspec/matchers'
require 'rdf/rdfa'

def normalize(graph)
  case graph
  when RDF::Queryable then graph
  when IO, StringIO
    RDF::Graph.new.load(graph, base_uri: @info.action)
  else
    # Figure out which parser to use
    g = RDF::Repository.new
    reader_class = detect_format(graph)
    reader_class.new(graph, base_uri: @info.action).each {|s| g << s}
    g
  end
end

Info = Struct.new(:id, :debug, :action, :result)

RSpec::Matchers.define :be_equivalent_graph do |expected, info|
  match do |actual|
    @info = if (info.id rescue false)
      info
    elsif info.is_a?(Hash)
      Info.new(info[:id], info[:debug], info[:action], info[:result])
    else
      Info.new(info, info.to_s)
    end
    @info.debug = Array(@info.debug).join("\n")
    @expected = normalize(expected)
    @actual = normalize(actual)
    @actual.isomorphic_with?(@expected) rescue false
  end
  
  failure_message do |actual|
    "#{@info.inspect + "\n"}" +
    if @expected.is_a?(RDF::Enumerable) && @actual.size != @expected.size
      "Graph entry count differs:\nexpected: #{@expected.size}\nactual:   #{@actual.size}\n"
    elsif @expected.is_a?(Array) && @actual.size != @expected.length
      "Graph entry count differs:\nexpected: #{@expected.length}\nactual:   #{@actual.size}\n"
    else
      "Graph differs\n"
    end +
    "Expected:\n#{@expected.dump(:ttl, standard_prefixes: true, prefixes: {'' => @info.action + '#'})}" +
    "Results:\n#{@actual.dump(:ttl, standard_prefixes: true, prefixes: {'' => @info.action + '#'})}" +
    (@info.debug ? "\nDebug:\n#{@info.debug}" : "")
  end  
end

RSpec::Matchers.define :pass_query do |expected, info|
  match do |actual|
    @info = if (info.id rescue false)
      info
    elsif info.is_a?(Hash)
      Info.new(info[:id], info[:debug], info[:action], info.fetch(:result, RDF::Literal::TRUE))
    end
    @info.debug = Array(@info.debug).join("\n")

    @expected = expected.respond_to?(:read) ? expected.read : expected

    require 'sparql'
    query = SPARQL.parse(@expected)
    @results = actual.query(query)

    @results == @info.result
  end

  failure_message do |actual|
    "#{@info.inspect + "\n"}" +
    if @results.nil?
      "Query failed to return results"
    elsif !@results.is_a?(RDF::Literal::Boolean)
      "Query returned non-boolean results"
    elsif @info.result != @results
      "Query returned false (expected #{@info.result})"
    else
      "Query returned true (expected #{@info.result})"
    end +
    "\n#{@expected}" +
    "\nResults:\n#{@actual.dump(:ttl, standard_prefixes: true, prefixes: {'' => @info.action + '#'})}" +
    "\nDebug:\n#{@info.debug}"
  end  

  failure_message_when_negated do |actual|
    "#{@info.inspect + "\n"}" +
    if @results.nil?
      "Query failed to return results"
    elsif !@results.is_a?(RDF::Literal::Boolean)
      "Query returned non-boolean results"
    elsif @info.expectedResults != @results
      "Query returned false (expected #{@info.result})"
    else
      "Query returned true (expected #{@info.result})"
    end +
    "\n#{@expected}" +
    "\nResults:\n#{@actual.dump(:ttl, standard_prefixes: true, prefixes: {'' => @info.action + '#'})}" +
    "\nDebug:\n#{@info.debug}"
  end  
end

RSpec::Matchers.define :produce do |expected, info = []|
  match do |actual|
    expect(actual).to eq expected
  end
  
  failure_message do |actual|
    "Expected: #{expected.is_a?(String) ? expected : expected.to_json(JSON_STATE)}\n" +
    "Actual  : #{actual.is_a?(String) ? actual : actual.to_json(JSON_STATE)}\n" +
    #(expected.is_a?(Hash) && actual.is_a?(Hash) ? "Diff: #{expected.diff(actual).to_json(JSON_STATE)}\n" : "") +
    "Processing results:\n#{info.join("\n")}"
  end
end
