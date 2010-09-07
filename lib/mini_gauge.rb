# === About this module ===
#
# This module is designed to make it easy to visualize complex data.  It does this by generating Graphviz files using the dot syntax.
#
# It is not designed for everyday use however, so to use it you must first call:
#  MiniGauge.enable!
#
# It adds a few methods to instance objects of ActiveRecord, the most useful is to_dot_notation, which will accept a list of
# includes similar to the parameters for a find() operation.
#
# Eg:
#  MemberProduct.last.to_dot_notation(:include =>  [:product, {:invoice_item => :invoice}])
#
# will return something like:
#
# digraph MemberProduct_131299 {
#   graph[overlap=false, splines=true]
#   "MemberProduct_131299" [shape=Mrecord, label="{MemberProduct_131299|id: 131299\lmembership_id: 46857\lproduct_id: 3\lproduct_type: Product \l}" ] 
#   "Donation_3" [shape=Mrecord, label="{Donation_3|id: 3\lname: Donation\lposition: 3\lprice_in_cents: 0\lrevenue_account_id: 3\ltype: Donation \l}" ] 
#   "InvoiceItem_567108" [shape=Mrecord, label="{InvoiceItem_567108|discount_in_cents: 0\lgross_price_in_cents: 0\lid: 567108\linvoice_id: 261641\lnet_price_in_cents: 0\lprice_in_cents: 0\lproduct_id: 131299\lproduct_type: MemberProduct\lquantity: 1 }" ] 
#   "Invoice_261641" [shape=Mrecord, label="{Invoice_261641|id: 261641\linvoiceable_id: 405\linvoiceable_type: Person\lnumber: 261641\lproforma: true }" ] 
# 
# 
#   "Donation_3" -> "MemberProduct_131299" 
#   "Invoice_261641" -> "InvoiceItem_567108" 
#   "InvoiceItem_567108" -> "MemberProduct_131299" 
# }
#
# which can then turned into a graph.
#
# Or, to get a complete set of memberships and member products

# doc = Organization.find(400).to_dot_notation(:include => {
#   :memberships => [
#     {:invoice_item => :invoice}, 
#     {:member_products => [
#         :product, 
#         {:invoice_item => :invoice}
#       ]
#     }
#   ]
# })
# 
# File.open("big_org.dot", 'w') {|f| f.write(doc) }
#
# to_dot_notation also accepts a block and passes the graph object to it, in case there are extra details to add.
# For example, to only do some of the member products try this:
#   @org_membership = Membership::Organizational::Base.find(400)
#   doc = @org_membership.to_dot_notation(:include => {:member => :people}) do |graph|
#     @org_membership.member_products.contact_reps.each do |cr_mpr|
#       graph.add(:source => @org_membership, :destination => cr_mpr, :label => "member_products.contact_reps")
#       cr_mpr.fill_dot_graph(graph, :include => [{:product => :member}, {:invoice_item => :invoice}])
#     end
#   end
#
# Classes can also be exported to dot notation, where the attributes and active record relations
# will be displayed
#
# They work the same way, at the class level:
#  doc = Membership::Organizational::Base.to_dot_notation
#
# By default only one level of relations is fetched, but if more are desired to_dot_notation will also accept a block:
#
#  doc = Membership::Organizational::Base.to_dot_notation do |graph|
#    Invoice.fill_with_relations(graph)
#  end
#
#
module MiniGauge
  
  HIDDEN_FIELDS = [ "created_at", "created_on", "updated_at", "updated_on",
    "lock_version", "type", "id", "position", "parent_id", "lft", 
    "rgt", "quote", "template", "salt", "persistence_token", "crypted_password", "current_login_at"]
  
  # Include this module in AR Base
  def self.enable!
    ActiveRecord::Base.send(:include, MiniGauge)
  end
  
  def self.included(base)
    base.send :include, InstanceMethods
    base.extend ClassMethods
  end
  
  # From Railroad, an object to hold our nodes and edges,
  # also to export them on demand
  class Graph
    attr_accessor :graph_type, :show_label, :nodes, :edges, :title, :description
    
    def initialize(opts = {})
      @graph_type = opts[:graph_type] || 'Model'
      @show_label = opts[:show_label] || true
      @title = opts[:title] || "#{@graph_type} diagram"
      @description = opts[:description] || ''
      @nodes = []
      @edges = []
      
      # Designed to work with the other class and instance methods on AR objects
      # to make adding nodes and edges easier.  Allows you to do something like
      # @graph.nodes << Invoice.first
      @nodes.instance_eval(%Q(
        def <<(item)
          if item.respond_to?(:dot_node_definition)
            super(item.dot_node_definition)
          else
            super(item)
          end
        end
      ))
      
      # Makes building graphs easier, allows you to do something like
      # @graph.edges << {:source => Person.first, :destination => Person.first.organization}
      @edges.instance_eval(%Q(
        def <<(item)
          if item.is_a? Hash
            if item[:source] && item[:source].respond_to?(:dot_node_name)
              item[:source] = item[:source].dot_node_name
            end
            
            if item[:destination] && item[:destination].respond_to?(:dot_node_name)
              item[:destination] = item[:destination].dot_node_name
            end
          end
          super(item)
        end
      ))
      
    end
    
    # Add an item to the graph, expects a source node and destination node or a label if there is no destination
    def add(opts)
      raise ArgumentError.new("Must supply :source and :destination") unless opts.is_a?(Hash) && opts.keys.include?(:source) && opts.keys.include?(:destination)
      raise ArgumentError.new("Cannot supply a nil :destination without a label") if opts[:destination].nil? && opts[:label].nil?
      
      if opts[:destination].nil?
        node_name = "#{opts[:label].underscore}_#{opts.object_id}"
        @nodes << self.nil_node_definition(:label => opts[:label], :name => node_name)
        @edges << {:destination => node_name, :source => opts[:source], :empty_rec => true}
      else
        @nodes<<opts[:source] unless @nodes.any?{|x| opts[:source].dot_node_name == x[:name] }
        @nodes<<opts[:destination] unless @nodes.any?{|x| opts[:destination].dot_node_name == x[:name] }
        @edges<<opts
      end
    end
    
    # Returns a node definition for an empty node
    def nil_node_definition(opts)
      raise ArgumentError.new("Must supply at least :name or :label") unless opts.is_a?(Hash) && (opts.keys.include?(:name) || opts.keys.include?(:label))
      
      {:name => (opts[:name] || opts[:label].underscore), :label => (opts[:label] || opts[:name].humanize.titleize), :attributes => ["none"], :options => {:color => "gray61"}}
    end

    # Returns a string representing the DOT graph
    def to_dot_notation
      header = "digraph #{@graph_type.downcase}_diagram {\n" +
               "\tgraph[overlap=false, splines=true]\n"
      header += dot_label if @show_label
      
      uniq_nodes = @nodes.inject([]) { |result,h| result << h unless result.include?(h); result }
      uniq_edges = @edges.inject([]) { |result,h| result << h unless result.include?(h); result }
      
      return header +
             uniq_nodes.map{|node| format_node(node)}.to_s + "\n" + 
             uniq_edges.map{|edge| format_edge(edge)}.to_s +
             "}\n"
    end


    # Build diagram label
    def dot_label
      return "\t_diagram_info [shape=\"plaintext\", " +
             "label=\"#{@title} \\l" +
             "Date: #{Time.now.strftime "%b %d %Y - %H:%M"}\\l" + 
             "Migration version: " +
             "#{ActiveRecord::Migrator.current_version}\\l" +
             "Description: #{@description}\\l" + 
             "\\l\", fontsize=14]\n"
    end
    
    # Take a node (hash) and format it into dot notation
    def format_node(node)
      node[:options] ||= {}
      node[:options][:shape] = "Mrecord"
      node[:options][:label] = %Q({#{(node[:label] || node[:name])} | #{node[:attributes].join('\l')} \\l} )
      opts = node[:options].collect{|k,v| %Q(#{k}="#{v}") }.join(", ")
      return %Q(\t"#{node[:name]}" [#{opts}]\n)
    end
    
    # Take an edge (hash) and format it into dot notation
    def format_edge(edge)
      edge[:options] ||= {}
      edge[:options][:label] = edge[:label] unless edge[:label].blank?
      edge[:options].merge!({:style => "dotted", :color => "gray61"}) if edge[:empty_rec]
      case edge[:type]
        when 'one-one'
             edge[:options].merge!({:arrowtail => "odot", :arrowhead => "dot", :dir => "both"})
        when 'one-many'
             edge[:options].merge!({:arrowtail => "crow", :arrowhead => "dot", :dir => "both"})
        when 'many-many'
             edge[:options].merge!({:arrowtail => "crow", :arrowhead => "crow", :dir => "both"})
        when 'is-a'
             edge[:options].merge!({:arrowtail => "onormal", :arrowhead => "none"})
      end
      opts = edge[:options].collect{|k,v| %Q(#{k}="#{v}") }.join(", ")
      return %Q( "#{edge[:source]}" -> "#{edge[:destination]}" [#{opts}]\n )
    end 
    
    
  end
  
  
  
  module ClassMethods
    
    # Returns the name of this for graph nodes
    def dot_node_name
      self.name
    end
    
    # Returns the attributes of this node for dot graphs
    def dot_node_attributes
      
      hidden_fields = MiniGauge::HIDDEN_FIELDS << "#{self.table_name}_count"

      return self.content_columns.reject{|x| hidden_fields.include?(x.name)}.collect{ |col|
        "#{col.name} :#{col.type.to_s}"
      }
      
    end
    
    # Accepts a Graph object and fills it with the relations for this object
    def fill_with_relations(dot_graph)
      self.reflect_on_all_associations.each do |assoc|
        
        if assoc.class_name == assoc.name.to_s.singularize.camelize
          assoc_name = ''
        else
          assoc_name = assoc.name.to_s
        end
        
        if assoc.macro.to_s == 'has_one' || assoc.macro.to_s == 'belongs_to'
          assoc_type = 'one-one'
        elsif assoc.macro.to_s == 'has_many' && (! assoc.options[:through])
          assoc_type = 'one-many'
        else # habtm or has_many, :through
          assoc_type = 'many-many'
        end 
        
        if assoc.options[:polymorphic]
          dot_graph.nodes << {:name => assoc.class_name, :attributes => ["polymorphic record"], :options => {:color => "gray61"}}
          dot_graph.edges << {:empty_rec => true, :source => self.dot_node_name, :destination => assoc.class_name, :type => assoc_type, :label => assoc_name }
        else
          dot_graph.nodes << {:name => assoc.klass.dot_node_name, :attributes => assoc.klass.dot_node_attributes}
          dot_graph.edges << {:source => self.dot_node_name, :destination => assoc.klass.dot_node_name, :type => assoc_type, :label => assoc_name }
        end
        
      end
    end
    
    # Creats a dot node graph and fills it with the relations for this object.  Returns a string representing the graph.
    # Will accept a block which passes the Graph object in case there are other relations to add.
    def to_dot_notation(opts = {})
      @graph = MiniGauge::Graph.new(opts)
      
      @graph.nodes << {:name => self.dot_node_name, :attributes => self.dot_node_attributes}
      
      fill_with_relations(@graph)
      
      yield(@graph) if block_given?
      
      return @graph.to_dot_notation
    
    end
        
  end
  
  module InstanceMethods
    
    # Returns a node name for the current object, used when creating relations and in definitions
    def dot_node_name
      "#{self.class.name.to_s}_#{self.id || self.object_id}"
    end
    
    # Returns a string used as the node description in the graph by inspecting the instanece attributes
    def dot_node_attributes
      
      hidden_fields = MiniGauge::HIDDEN_FIELDS << "#{self.class.table_name}_count"

      return self.attributes.reject{|k,v| hidden_fields.include?(k) || v.nil? }.collect{ |k,v|
        "#{k}: #{v.to_s.gsub(/['"]/,'')}"
      }
      
    end
    
    # Returns a node definition for the current object.  For example:    
    def dot_node_definition
      {:name => self.dot_node_name, :label => self.dot_node_name, :attributes => self.dot_node_attributes }
    end
    
    # Optionally pass a block to manually fill in details.
    #
    # @org_membership.to_dot_notation(:include => {:member => :people}, :title => "An organization with a transferred Contact Representative", :description => "Organizations can transfer Contact Representative memberships to other people.  This graph shows what the data looks like after a transfer" ) do |graph|
    #   @org_membership.member_products.contact_reps.each do |cr_mpr|
    #     graph.add(:source => @org_membership, :destination => cr_mpr, :label => "member_products.contact_reps")
    #     cr_mpr.fill_dot_graph(graph, :include => [{:product => :member}, {:invoice_item => :invoice}])
    #   end
    # end
    def to_dot_notation(opts = {})
      @graph = MiniGauge::Graph.new(opts)
      
      self.fill_dot_graph(@graph, opts)
      
      yield(@graph) if block_given?
      
      return @graph.to_dot_notation
    
    end
    
    # Takes a graph and fills in the graph given the options by inspecting the relations
    def fill_dot_graph(dot_graph, opts={})
      
      dot_graph.nodes << self.dot_node_definition
      
      # Set up to allow something like this:
      #     :include => [:product, {:invoice_item => :invoice}]
      # ie, about the same as ar associations
      opts[:include] = Array(opts[:include]) unless opts[:include].respond_to?(:each)
      opts[:include].each do |relation, relation_opts|
        if relation.is_a?(Hash) || relation.is_a?(Array)
          relation.each do |name, sub_opts|
            # We do the funny bits with data here because calling Array() on it makes AR complain
            data = self.send(name.to_sym) 
            data = [data] unless data.respond_to?(:each)
            data = [nil] if data.empty?  #make sure we have something to show for this leg of the graph
            data.each do |obj|
              if obj.nil? # It was in the options, but there is nothing found for it, eg self.product returns nil
                dot_graph.add(:destination => obj, :source => self, :label => name.to_s)
              else
                # Here is where we recurse, rolling everything into our list of nodes and edges.
                obj.fill_dot_graph(dot_graph, :include => sub_opts) 
                dot_graph.edges << {:destination => obj.dot_node_name, :source => dot_node_name, :label => name.to_s.humanize}
              end
            end
          end
        else
          data = self.send(relation.to_sym)
          data = [data] unless data.respond_to?(:each)
          data = [nil] if data.empty? #make sure we have something to show for this leg of the graph
          data.each do |obj|
            if relation_opts #more recursion here
              obj.fill_dot_graph(dot_graph, :include => relation_opts)
              dot_graph.edges << {:destination => obj.dot_node_name, :source => dot_node_name, :label => relation.to_s.humanize}
            else
              dot_graph.add(:destination => obj, :source => self, :label => relation.to_s.humanize)
            end
          end
        end
      end
      
    end
    
    
  end
  
end