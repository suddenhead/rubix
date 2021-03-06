module Rubix
  
  class Item < Model

    #
    # == Properties & Finding ==
    #

    # The numeric codes for the various item types.
    #
    # Items without a type will be set to 'zabbix'.
    TYPE_CODES = {
      :zabbix     => 0,
      :snmpv1     => 1,
      :trapper    => 2,
      :simple     => 3,
      :snmpv2c    => 4,
      :internal   => 5,
      :snmpv3     => 6,
      :active     => 7,
      :aggregate  => 8,
      :httptest   => 9,
      :external   => 10,
      :db_monitor => 11,
      :ipmi       => 12,
      :ssh        => 13,
      :telnet     => 14,
      :calculated => 15
    }.freeze
    TYPE_NAMES = TYPE_CODES.invert.freeze

    # The numeric codes for the value types of a Zabbix item.
    #
    # This Hash is used by ZabbixPipe#value_code_from_value to
    # dynamically set the type of a value when creating a new Zabbix
    # item.
    VALUE_CODES = {
      :float        => 0,         # Numeric (float)
      :character    => 1,         # Character
      :log_line     => 2,         # Log
      :unsigned_int => 3,         # Numeric (unsigned)
      :text         => 4          # Text
    }.freeze
    VALUE_NAMES = VALUE_CODES.invert.freeze

    # The numeric codes for the data types of a Zabbix item.
    #
    # The default will be <tt>:decimal</tt>
    DATA_CODES = {
      :decimal     => 0,
      :octal       => 1,
      :hexadecimal => 2
    }.freeze
    DATA_NAMES = DATA_CODES.invert.freeze

    # The numeric codes for the status of a Zabbix item.
    #
    # The default will be <tt>:active</tt>
    STATUS_CODES = {
      :active        => 0,
      :disabled      => 1,
      :not_supported => 3
    }.freeze
    STATUS_NAMES = STATUS_CODES.invert.freeze

    # The numeric codes for the delta type
    #
    # The default will be <tt>:as_is</tt>
    DELTA_CODES = {
      :as_is			=> 0,
      :speed_per_second	=> 1,
      :simple_change	=> 2
    }.freeze
    DELTA_NAMES = DELTA_CODES.invert.freeze

    # Return the +value_type+ name (:float, :text, &c.) for a Zabbix
    # item's value type by examining the given +value+.
    def self.value_type_from_value value
      case
      when value =~ /\d+/       then :unsigned_int
      when value =~ /-?[\d\.]+/ then :float
      when value.include?("\n") then :text
      else :character
      end
    end

    # Return the +value_type+'s numeric code for a Zabbix item's value
    # type by examining the given +value+.
    def self.value_code_from_value value
      self::VALUE_CODES[value_type_from_value(value)]
    end
    
    attr_accessor :key, :description, :units, :multiply_by, :data_type, :history, :trends, :status, :frequency, :delta
    attr_writer :type, :value_type

    def initialize properties={}
      super(properties)
      self.key             = properties[:key]
      self.description     = properties[:description]
      self.type            = properties[:type]
      self.units           = properties[:units]
      self.multiply_by     = properties[:multiply_by]
      self.value_type      = properties[:value_type]
      self.data_type       = properties[:data_type]
      self.history         = properties[:history]
      self.trends          = properties[:trends]
      self.status          = properties[:status]
      self.frequency       = properties[:frequency]
  	  self.delta	    	   = properties[:delta]

      self.host            = properties[:host]
      self.host_id         = properties[:host_id]

      self.template        = properties[:template]
      self.template_id     = properties[:template_id]
      
      self.applications    = properties[:applications]
      self.application_ids = properties[:application_ids]
    end

    def resource_name
      "#{self.class.resource_name} #{self.key || self.id}"
    end

    def value_type
      @value_type ||= :character
    end

    def data_type
      @data_type ||= :decimal
    end

    def type
      @type ||= :zabbix
    end

  	def delta
	    @delta ||= :as_is
  	end

    #
    # == Associations ==
    #

    include Associations::BelongsToHost
    include Associations::BelongsToTemplate
    include Associations::HasManyApplications

    #
    # == Requests == 
    #
    
    def create_params
      {
        :hostid       => host_id,
        :description  => (description || 'Unknown'),
        :type         => self.class::TYPE_CODES[type],
        :key_         => key,
        :value_type   => self.class::VALUE_CODES[value_type],
      }.tap do |p|
        p[:applications] = application_ids if application_ids
        p[:units]        = units                 if units
        p[:data_type]    = self.class::DATA_CODES[data_type] if data_type
        p[:history]      = history.to_i if history
        p[:trends]       = trends.to_i if trends
        p[:status]       = self.class::STATUS_CODES[status] if status
        p[:delay]        = frequency if frequency
        p[:delta]        = self.class::DELTA_CODES[delta] if delta
        if multiply_by && multiply_by.to_f != 0.0
          p[:multiplier] = 1
          p[:formula]    = multiply_by.to_f
        end
      end
    end

    def self.get_params
      super().merge(:select_applications => :refer)
    end
    
    def self.find_params options={}
      super().merge({
                      :filter => {
                        :key_ => options[:key],
                        :id   => options[:id]
                      }
                    }.tap do |o|
                      o[:hostids] = [options[:host_id]] if options[:host_id]
                    end
                    )
    end

    def self.build item
      new({
            :id              => item[id_field].to_i,
            :host_id         => item['hostid'].to_i,
            :description     => item['description'],
            :type            => TYPE_NAMES[item['type'].to_i],
            :value_type      => VALUE_NAMES[item['value_type'].to_i],
            :data_type       => DATA_NAMES[item['data_type'].to_i],
            :history         => item['history'].to_i,
            :trends          => item['trends'].to_i,
            :status          => STATUS_NAMES[item['status'].to_i],
            :application_ids => (item['applications'] || []).map { |app| app['applicationid'].to_i },
            :key             => item['key_'],
            :units           => item['units'],
            :frequency       => item['delay'].to_i,
            :multiply_by     => ((item['multiplier'].to_i == 1 && item['formula'].to_f != 0.0) ? item['formula'].to_f : nil),
	      		:delta			     => DELTA_NAMES[item['delta'].to_i]
          })
    end

    def time_series options={}
      TimeSeries.find(options.merge(:item_id => self.id, :item => self))
    end
    
  end
end
