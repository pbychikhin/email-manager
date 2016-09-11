-- MySQL dump 10.13  Distrib 5.1.63, for portbld-freebsd8.2 (i386)
--
-- Host: localhost    Database: devel_postfix2
-- ------------------------------------------------------
-- Server version	5.1.63

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `devel_postfix2`
--

/*!40000 DROP DATABASE IF EXISTS `devel_postfix2`*/;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `devel_postfix2` /*!40100 DEFAULT CHARACTER SET ascii */;

USE `devel_postfix2`;

--
-- Table structure for table `account`
--

DROP TABLE IF EXISTS `account`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `account` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `domain_id` bigint(20) unsigned NOT NULL,
  `name` varchar(255) NOT NULL,
  `password` varchar(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `password_enabled` tinyint(4) NOT NULL DEFAULT '0',
  `fullname` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `spooldir` char(40) NOT NULL,
  `created` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `accessed` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `public` tinyint(1) NOT NULL DEFAULT '1',
  `ad_guid` binary(16) DEFAULT NULL,
  `ad_sync_enabled` tinyint(4) NOT NULL DEFAULT '1',
  `ad_sync_required` tinyint(4) NOT NULL DEFAULT '0',
  `ad_time_changed` varbinary(32) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `spooldir` (`spooldir`),
  UNIQUE KEY `name_domain` (`name`,`domain_id`),
  UNIQUE KEY `uk_ac_ad_guid` (`ad_guid`),
  KEY `fullname` (`fullname`),
  KEY `domain_id` (`domain_id`),
  CONSTRAINT `fk_domain_id` FOREIGN KEY (`domain_id`) REFERENCES `domain` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `alias_name`
--

DROP TABLE IF EXISTS `alias_name`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `alias_name` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `fullname` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `active` tinyint(1) DEFAULT '1',
  `public` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `alias_value`
--

DROP TABLE IF EXISTS `alias_value`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `alias_value` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name_id` bigint(20) unsigned NOT NULL,
  `value` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `active` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name_value` (`name_id`,`value`),
  CONSTRAINT `fk_alias_name_id` FOREIGN KEY (`name_id`) REFERENCES `alias_name` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `domain`
--

DROP TABLE IF EXISTS `domain`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `domain` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `spooldir` char(40) NOT NULL,
  `created` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `public` tinyint(1) NOT NULL DEFAULT '1',
  `ad_guid` binary(16) DEFAULT NULL,
  `ad_sync_enabled` tinyint(4) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  UNIQUE KEY `spooldir` (`spooldir`),
  UNIQUE KEY `uk_dm_ad_guid` (`ad_guid`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `sysinfo`
--

DROP TABLE IF EXISTS `sysinfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `sysinfo` (
  `pname` varchar(64) NOT NULL,
  `pvalue` varchar(64) NOT NULL,
  UNIQUE KEY `pname` (`pname`)
) ENGINE=InnoDB DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `tab_defaults`
--

DROP TABLE IF EXISTS `tab_defaults`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tab_defaults` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `tab_name` varchar(255) NOT NULL,
  `tab_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `tab_name` (`tab_name`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `usn_tracking`
--

DROP TABLE IF EXISTS `usn_tracking`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `usn_tracking` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `domain_id` bigint(20) unsigned NOT NULL,
  `dit_invocation_id` varbinary(256) NOT NULL,
  `dit_usn` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ut_domain_dit` (`domain_id`,`dit_invocation_id`),
  CONSTRAINT `fk_ut_domain_id` FOREIGN KEY (`domain_id`) REFERENCES `domain` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=ascii;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping routines for database 'devel_postfix2'
--
/*!50003 DROP FUNCTION IF EXISTS `GetAccountSpoolDir` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `GetAccountSpoolDir`(sp_name VARCHAR(510), sp_caller ENUM('smtp', 'pop', 'imap')) RETURNS varchar(255) CHARSET ascii
    MODIFIES SQL DATA
BEGIN
	    DECLARE sp_acname VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'name');
	    DECLARE sp_acdomain VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'domain');
	    IF (sp_acdomain IS NULL) THEN SET sp_acdomain =
		(SELECT name FROM domain WHERE id = 
		(SELECT tab_id FROM tab_defaults WHERE tab_name = 'domain'));
	    END IF;
		IF (sp_caller = 'pop' OR sp_caller = 'imap') THEN
			UPDATE account SET accessed = CURRENT_TIMESTAMP WHERE name = sp_acname AND active = TRUE AND
			domain_id = (SELECT id FROM domain WHERE name = sp_acdomain AND active = TRUE);
		END IF;
	    RETURN(SELECT CONCAT(domain.spooldir, '/', account.spooldir) FROM account, domain
		WHERE account.name = sp_acname AND account.active = TRUE AND domain.name = sp_acdomain AND
		domain.active = TRUE AND account.domain_id = domain.id);
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP FUNCTION IF EXISTS `GetFullSysName` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `GetFullSysName`() RETURNS varchar(256) CHARSET ascii
    READS SQL DATA
    SQL SECURITY INVOKER
BEGIN
		DECLARE sysname varchar(64);
		DECLARE vmajor varchar(64);
		DECLARE vminor varchar(64);
		DECLARE vpatch varchar(64);
		SELECT pvalue INTO sysname FROM sysinfo WHERE pname = 'sysname';
		SELECT pvalue INTO vmajor FROM sysinfo WHERE pname = 'vmajor';
		SELECT pvalue INTO vminor FROM sysinfo WHERE pname = 'vminor';
		SELECT pvalue INTO vpatch FROM sysinfo WHERE pname = 'vpatch';
		RETURN(LOWER(CONCAT(sysname, ':', vmajor, ':', vminor, ':', vpatch)));
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP FUNCTION IF EXISTS `GetNamePart` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `GetNamePart`(sp_name VARCHAR(510), sp_delim CHAR(1), sp_partname CHAR(10)) RETURNS varchar(255) CHARSET ascii
    READS SQL DATA
    SQL SECURITY INVOKER
BEGIN
	    DECLARE sp_delim_pos INT DEFAULT LOCATE(sp_delim, sp_name);
	    IF (sp_partname = 'domain') THEN
		IF (sp_delim_pos = 0) THEN RETURN(NULL); END IF;
		IF (CHAR_LENGTH(sp_name) = sp_delim_pos) THEN RETURN(NULL); END IF;
		RETURN(SUBSTR(sp_name FROM sp_delim_pos + 1));
	    END IF;
	    IF (sp_partname = 'name') THEN
		IF (sp_delim_pos = 1) THEN RETURN(NULL); END IF;
		IF (sp_delim_pos = 0) THEN RETURN(sp_name); END IF;
		RETURN(SUBSTR(sp_name FROM 1 FOR sp_delim_pos - 1));
	    END IF;
	RETURN(NULL);
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP FUNCTION IF EXISTS `sasl_getlogin` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `sasl_getlogin`(sp_name VARCHAR(510)) RETURNS varchar(510) CHARSET ascii
    READS SQL DATA
    SQL SECURITY INVOKER
BEGIN
	DECLARE sp_acname VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'name');
	DECLARE sp_acdomain VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'domain');
	DECLARE sp_defaultdomain VARCHAR(255) DEFAULT (SELECT name FROM domain WHERE id = (SELECT tab_id
		FROM tab_defaults WHERE tab_name = 'domain'));
	DECLARE sp_logins VARCHAR(765) DEFAULT NULL;
	IF (sp_acname IS NULL OR sp_acdomain IS NULL) THEN
		RETURN(NULL);
	END IF;	
	SELECT CONCAT(account.name, '@', domain.name) FROM account, domain
		WHERE account.name = sp_acname AND account.active = TRUE AND domain.name = sp_acdomain AND
		domain.active = TRUE AND account.domain_id = domain.id INTO sp_logins;
	IF (sp_logins IS NOT NULL AND sp_acdomain = sp_defaultdomain) THEN
		SET sp_logins = CONCAT(sp_logins, ',', GetNamePart(sp_logins, '@', 'name'));
	END IF;
	RETURN(sp_logins);
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP FUNCTION IF EXISTS `sasl_getpass` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `sasl_getpass`(sp_name VARCHAR(510)) RETURNS varchar(64) CHARSET ascii
    READS SQL DATA
    SQL SECURITY INVOKER
BEGIN
	    DECLARE sp_acname VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'name');
	    DECLARE sp_acdomain VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'domain');
	    IF (sp_acdomain IS NULL) THEN SET sp_acdomain =
		(SELECT name FROM domain WHERE id = 
		(SELECT tab_id FROM tab_defaults WHERE tab_name = 'domain'));
	    END IF;
	    RETURN(SELECT CONCAT(_ascii'{PLAIN}', password) FROM account, domain
		WHERE account.name = sp_acname AND domain.name = sp_acdomain AND domain.active = TRUE
			AND account.domain_id = domain.id AND account.active = TRUE AND account.password_enabled = TRUE);
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `account_add` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `account_add`(
		sp_domain varchar(255),
		sp_name varchar(255),
		sp_password varchar(64),
		sp_fullname varchar(255) CHARACTER SET utf8,
		sp_active tinyint(1),
		sp_public tinyint(1))
    MODIFIES SQL DATA
THISPROC: BEGIN
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (sp_domain IS NULL) THEN
			SELECT d.name INTO sp_domain FROM tab_defaults td, domain d
				WHERE td.tab_name = 'domain' AND d.id = td.tab_id;
		END IF;
		IF (sp_domain IS NULL) THEN
			COMMIT;
			SET @last_proc_state = 'NODOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM domain WHERE name = sp_domain)) THEN
			COMMIT;
			SET @last_proc_state = 'NXDOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (EXISTS(SELECT * FROM account WHERE name = sp_name AND domain_id = 
			(SELECT id FROM domain WHERE name = sp_domain))) THEN
			COMMIT;
			SET @last_proc_state = 'ACCEXISTS';
			LEAVE THISPROC;
		END IF;

		INSERT INTO account(domain_id, name, password, fullname, spooldir, created, modified, active, public,
						password_enabled, ad_sync_enabled)
			VALUES((SELECT id FROM domain WHERE name = sp_domain), sp_name, sp_password, sp_fullname,
				CONCAT(UUID(),'/'), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
				IFNULL(sp_active, DEFAULT(account.active)),
				IFNULL(sp_public, DEFAULT(account.public)),
				TRUE, FALSE);
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `account_del` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `account_del`(
		sp_domain varchar(255),
		sp_name varchar(255))
    MODIFIES SQL DATA
THISPROC: BEGIN
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (sp_domain IS NULL) THEN
			SELECT d.name INTO sp_domain FROM tab_defaults td, domain d
				WHERE td.tab_name = 'domain' AND d.id = td.tab_id;
		END IF;
		IF (sp_domain IS NULL) THEN
			COMMIT;
			SET @last_proc_state = 'NODOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM domain WHERE name = sp_domain)) THEN
			COMMIT;
			SET @last_proc_state = 'NXDOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM account WHERE name = sp_name AND
			domain_id = (SELECT id FROM domain WHERE name = sp_domain))) THEN
			COMMIT;
			SET @last_proc_state = 'NXACCOUNT';
			LEAVE THISPROC;
		END IF;

		DELETE FROM account WHERE name = sp_name AND domain_id = (SELECT id FROM domain WHERE name = sp_domain);
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `account_mod` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `account_mod`(
		sp_domain varchar(255),
		sp_name varchar(255),
		sp_newname varchar(255),
		sp_password varchar(64),
		sp_fullname varchar(255) CHARACTER SET utf8,
		sp_active tinyint(1),
		sp_public tinyint(1),
		sp_password_enabled TINYINT,
		sp_ad_sync_enabled TINYINT)
    MODIFIES SQL DATA
THISPROC: BEGIN
		DECLARE old_name varchar(255);
		DECLARE old_password varchar(64);
		DECLARE old_fullname varchar(255) CHARACTER SET utf8;
		DECLARE old_active tinyint(1);
		DECLARE old_public tinyint(1);
		DECLARE old_password_enabled TINYINT;
		DECLARE old_ad_sync_enabled TINYINT;
		DECLARE old_ad_sync_required TINYINT;
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (sp_domain IS NULL) THEN
			SELECT d.name INTO sp_domain FROM tab_defaults td, domain d
				WHERE td.tab_name = 'domain' AND d.id = td.tab_id;
		END IF;
		IF (sp_domain IS NULL) THEN
			COMMIT;
			SET @last_proc_state = 'NODOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM domain WHERE name = sp_domain)) THEN
			COMMIT;
			SET @last_proc_state = 'NXDOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (COALESCE(sp_newname, sp_password, sp_password_enabled, sp_fullname, sp_active, sp_public,
			sp_ad_sync_enabled) IS NULL) THEN
			COMMIT;
			SET @last_proc_state = 'NONEWDATA';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM account WHERE name = sp_name AND
			domain_id = (SELECT id FROM domain WHERE name = sp_domain))) THEN
			COMMIT;
			SET @last_proc_state = 'NXACCOUNT';
			LEAVE THISPROC;
		END IF;

		IF (STRCMP(sp_name, sp_newname) != 0 AND EXISTS(SELECT * FROM account WHERE name = sp_newname AND
			domain_id = (SELECT id FROM domain WHERE name = sp_domain))) THEN
			COMMIT;
			SET @last_proc_state = 'ACCEXISTS';
			LEAVE THISPROC;
		END IF;

		SELECT name, password, password_enabled, fullname, active, public, ad_sync_enabled, ad_sync_required
			INTO old_name, old_password, old_password_enabled, old_fullname, old_active, old_public,
				old_ad_sync_enabled, old_ad_sync_required
			FROM account WHERE name = sp_name AND domain_id = (SELECT id FROM domain WHERE name = sp_domain);
		UPDATE account SET
			name = IFNULL(sp_newname, old_name),
			password = IFNULL(sp_password, old_password),
			fullname = IFNULL(sp_fullname, old_fullname),
			active = IFNULL(sp_active, old_active),
			public = IFNULL(sp_public, old_public),
			password_enabled = IFNULL(sp_password_enabled, old_password_enabled),
			ad_sync_enabled = IFNULL(sp_ad_sync_enabled, old_ad_sync_enabled),
			ad_sync_required = IF(sp_ad_sync_enabled = TRUE AND sp_ad_sync_enabled <> old_ad_sync_enabled, TRUE,
				old_ad_sync_required),
			modified = CURRENT_TIMESTAMP
			WHERE name = sp_name AND domain_id = (SELECT id FROM domain WHERE name = sp_domain);
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `alias_add` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `alias_add`(
		sp_name varchar(255),
		sp_value varchar(255), 
		sp_fullname varchar(255) CHARACTER SET utf8,
		sp_active tinyint(1),
		sp_public tinyint(1))
    MODIFIES SQL DATA
THISPROC: BEGIN
		DECLARE new_alias_name_created tinyint(1) DEFAULT 0;
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (EXISTS(SELECT * FROM alias_value WHERE value = sp_value AND name_id = 
			(SELECT id FROM alias_name WHERE name = sp_name))) THEN
			COMMIT;
			SET @last_proc_state = 'ALIEXISTS';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM alias_name WHERE name = sp_name)) THEN
			INSERT INTO alias_name(name, fullname, created, modified, active, public)
				VALUES(sp_name, sp_fullname, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
				IFNULL(sp_active, DEFAULT(alias_name.active)),
				IFNULL(sp_public, DEFAULT(alias_name.public)));
				SET new_alias_name_created = 1;
		END IF;

		INSERT INTO alias_value(name_id, value, created, modified, active)
			VALUES((SELECT id FROM alias_name WHERE name = sp_name), sp_value, CURRENT_TIMESTAMP,
			CURRENT_TIMESTAMP, IF(sp_active IS NOT NULL AND new_alias_name_created = 0, 
			sp_active, DEFAULT(alias_value.active)));
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `alias_del` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `alias_del`(
		sp_name varchar(255),
		sp_value varchar(255))
    MODIFIES SQL DATA
THISPROC: BEGIN
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;
		IF (sp_value IS NULL) THEN

			IF (NOT EXISTS(SELECT * FROM alias_name WHERE name = sp_name)) THEN
				COMMIT;
				SET @last_proc_state = 'NXALIAS';
				LEAVE THISPROC;
			END IF;

			DELETE FROM alias_name WHERE name = sp_name; 
		ELSE

			IF (NOT EXISTS(SELECT * FROM alias_value WHERE value = sp_value AND
				name_id = (SELECT id FROM alias_name WHERE name = sp_name))) THEN
				COMMIT;
				SET @last_proc_state = 'NXALIAS';
				LEAVE THISPROC;
			END IF;

			DELETE FROM alias_value WHERE value = sp_value AND name_id = (SELECT id FROM alias_name
				WHERE name = sp_name);
			IF (NOT EXISTS(SELECT * FROM alias_value WHERE name_id = (SELECT id FROM alias_name
				WHERE name = sp_name))) THEN
				DELETE FROM alias_name WHERE name = sp_name;
			END IF;
		END IF;
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `alias_mod` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `alias_mod`(
		sp_name varchar(255),
		sp_newname varchar(255),
		sp_value varchar(255), 
		sp_newvalue varchar(255),
		sp_fullname varchar(255) CHARACTER SET utf8,
		sp_active tinyint(1),
		sp_public tinyint(1))
    MODIFIES SQL DATA
THISPROC: BEGIN
		DECLARE old_name varchar(255);
		DECLARE old_value varchar(255);
		DECLARE old_fullname varchar(255) CHARACTER SET utf8;
		DECLARE old_active tinyint(1);
		DECLARE old_public tinyint(1);	
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;
		IF (sp_value IS NULL) THEN

			IF (COALESCE(sp_newname, sp_fullname, sp_active, sp_public) IS NULL) THEN
				COMMIT;
				SET @last_proc_state = 'NONEWDATA';
				LEAVE THISPROC;
			END IF;

			IF (NOT EXISTS(SELECT * FROM alias_name WHERE name = sp_name)) THEN
				COMMIT;
				SET @last_proc_state = 'NXALIAS';
				LEAVE THISPROC;
			END IF;

			IF (STRCMP(sp_name, sp_newname) != 0 AND
				EXISTS(SELECT * FROM alias_name WHERE name = sp_newname)) THEN
				COMMIT;
				SET @last_proc_state = 'ALIEXISTS';
				LEAVE THISPROC;
			END IF;

			SELECT name, fullname, active, public INTO old_name, old_fullname, old_active, old_public
				FROM alias_name WHERE name = sp_name;
			UPDATE alias_name SET
				name = IFNULL(sp_newname, old_name),
				fullname = IFNULL(sp_fullname, old_fullname),
				active = IFNULL(sp_active, old_active),
				public = IFNULL(sp_public, old_public),
				modified = CURRENT_TIMESTAMP
			WHERE name = sp_name;
		ELSE

			IF (COALESCE(sp_newvalue, sp_active) IS NULL) THEN
				COMMIT;
				SET @last_proc_state = 'NONEWDATA';
				LEAVE THISPROC;
			END IF;

			IF (NOT EXISTS(SELECT * FROM alias_value WHERE value = sp_value AND
				name_id = (SELECT id FROM alias_name WHERE name = sp_name))) THEN
				COMMIT;
				SET @last_proc_state = 'NXALIAS';
				LEAVE THISPROC;
			END IF;

			IF (STRCMP(sp_value, sp_newvalue) != 0 AND EXISTS(SELECT * FROM alias_value
				WHERE value = sp_newvalue AND name_id = (SELECT id FROM alias_name WHERE
				name = sp_name))) THEN
				COMMIT;
				SET @last_proc_state = 'ALIEXISTS';
				LEAVE THISPROC;
			END IF;

			SELECT value, active INTO old_value, old_active FROM alias_value WHERE
				value = sp_value AND name_id = (SELECT id FROM alias_name WHERE name = sp_name);
			UPDATE alias_value SET
				value = IFNULL(sp_newvalue, old_value),
				active = IFNULL(sp_active, old_active),
				modified = CURRENT_TIMESTAMP
			WHERE value = sp_value AND name_id = (SELECT id FROM alias_name WHERE name = sp_name);
		END IF;
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `domain_add` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `domain_add`(
		sp_name varchar(255),
		sp_active tinyint(1),
		sp_public tinyint(1))
    MODIFIES SQL DATA
THISPROC: BEGIN
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (EXISTS(SELECT * FROM domain WHERE name = sp_name)) THEN
			COMMIT;
			SET @last_proc_state = 'DOMAINEXISTS';
			LEAVE THISPROC;
		END IF;

		INSERT INTO domain(name, spooldir, created, modified, active, public, ad_sync_enabled)
			VALUES(sp_name, UUID(), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
				IF(sp_active IS NOT NULL, sp_active, DEFAULT(domain.active)),
				IF(sp_public IS NOT NULL, sp_public, DEFAULT(domain.public)),
				FALSE);
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `domain_del` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_VALUE_ON_ZERO' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `domain_del`(
		sp_name varchar(255))
    MODIFIES SQL DATA
THISPROC: BEGIN	
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (NOT EXISTS(SELECT * FROM domain WHERE name = sp_name)) THEN
			COMMIT;
			SET @last_proc_state = 'NXDOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (EXISTS(SELECT * FROM account WHERE domain_id = (SELECT id FROM domain WHERE name = sp_name))) THEN
			COMMIT;
			SET @last_proc_state = 'ACCEXISTS';
			LEAVE THISPROC;
		END IF;

		DELETE FROM domain WHERE name = sp_name;
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `domain_mod` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 PROCEDURE `domain_mod`(
		sp_name varchar(255),
		sp_newname varchar(255),
		sp_active tinyint(1),
		sp_public tinyint(1),
		sp_ad_sync_enabled TINYINT)
    MODIFIES SQL DATA
THISPROC: BEGIN
		DECLARE old_name varchar(255);
		DECLARE old_active tinyint(1);
		DECLARE old_public tinyint(1);
		DECLARE old_ad_sync_enabled TINYINT;
		SET @last_proc_state = 'NOPROBLEM';
		START TRANSACTION;

		IF (COALESCE(sp_newname, sp_active, sp_public, sp_ad_sync_enabled) IS NULL) THEN
			COMMIT;
			SET @last_proc_state = 'NONEWDATA';
			LEAVE THISPROC;
		END IF;

		IF (NOT EXISTS(SELECT * FROM domain WHERE name = sp_name)) THEN
			COMMIT;
			SET @last_proc_state = 'NXDOMAIN';
			LEAVE THISPROC;
		END IF;

		IF (STRCMP(sp_name, sp_newname) != 0 AND
			EXISTS(SELECT * FROM domain WHERE name = sp_newname)) THEN
			COMMIT;
			SET @last_proc_state = 'DOMAINEXISTS';
			LEAVE THISPROC;
		END IF;

		SELECT name, active, public, ad_sync_enabled INTO old_name, old_active, old_public, old_ad_sync_enabled
			FROM domain WHERE name = sp_name;
		UPDATE domain SET
			name = IFNULL(sp_newname, old_name),
			active = IFNULL(sp_active, old_active),
			public = IFNULL(sp_public, old_public),
			ad_sync_enabled = IFNULL(sp_ad_sync_enabled, old_ad_sync_enabled),
			modified = CURRENT_TIMESTAMP
			WHERE name = sp_name;
		COMMIT;
	END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2012-10-12 14:18:48

-- Populate table `sysinfo`
INSERT INTO sysinfo(pname, pvalue) VALUES('sysname', 'emailmgr');
INSERT INTO sysinfo(pname, pvalue) VALUES('vmajor', '3');
INSERT INTO sysinfo(pname, pvalue) VALUES('vminor', '0');
INSERT INTO sysinfo(pname, pvalue) VALUES('vpatch', '0');

-- Populate table `tab_defaults`
CALL domain_add('testdomain.org', TRUE, TRUE);
INSERT INTO tab_defaults(tab_name, tab_id) VALUES('domain', (SELECT MIN(id) FROM domain));
